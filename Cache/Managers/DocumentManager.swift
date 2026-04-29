import Foundation
import Combine
import UIKit
import os
import WidgetKit

@MainActor
class DocumentManager: ObservableObject {
    @Published var scraps: [Scrap] = []
    @Published var focusedScrapID: String?
    @Published var focusedScrapFilename: String?
    @Published var isReady = false
    // iCloud ubiquity-container status. When `false`, the user is either signed out
    // of iCloud, has disabled iCloud Drive for this app, or the container hasn't
    // finished provisioning. Without surfacing this, the app silently shows an
    // empty list and every keystroke is lost — indistinguishable from data loss.
    //
    // Defaults to `true` so the overlay doesn't flash on during the first frame
    // before the asynchronous probe completes; the common case is that iCloud
    // is available, and a transient false-negative is worse than a brief delay
    // to surface a genuine outage.
    @Published var iCloudAvailable: Bool = true

    private var documentObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var ubiquityIdentityObserver: NSObjectProtocol?

    private var hasBackgrounded = false
    private var isInitialLoad = true
    private var widgetReloadWorkItem: DispatchWorkItem?

    // Single canonical slot for the background-save task so rapid inactive/active
    // cycles can't leak overlapping identifiers between captured closure locals.
    private var backgroundSaveTaskID: UIBackgroundTaskIdentifier = .invalid

    // Cached container URL resolved by the async probe. Avoids a second
    // forUbiquityContainerIdentifier syscall on every directory access, and
    // keeps the "available" signal and the URL it resolved to consistent.
    private var ubiquityContainerURL: URL?

    private var documentsDirectoryURL: URL? {
        ubiquityContainerURL?.appendingPathComponent("Documents")
    }

    init() {
        // Observe identity changes (user signs out / switches iCloud accounts)
        // so the overlay reflects reality without requiring an app relaunch.
        ubiquityIdentityObserver = NotificationCenter.default.addObserver(
            forName: .NSUbiquityIdentityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.probeUbiquityAvailability()
            }
        }

        Task {
            // forUbiquityContainerIdentifier can block for hundreds of ms on first
            // launch while the daemon provisions the container; keep it off the
            // main actor so the first frame paints immediately.
            await probeUbiquityAvailabilityAsync()

            guard iCloudAvailable else {
                // No container — nothing to load. Still mark ready so the UI can
                // surface the unavailable state rather than spinning forever.
                isInitialLoad = false
                isReady = true
                return
            }

            // Step 1: Load existing scraps, prioritising the latest so the UI is interactive ASAP
            await loadScrapsInitial()

            // Step 2: Check if we need to create a new scrap
            if shouldCreateNewScrap() {
                // Long absence — check if last scrap is empty and replace if needed.
                // Load-bearing invariant: shouldCreateNewScrap() being true implies the
                // latest scrap's timestamp is from a prior calendar day, so it cannot
                // be one we just created this session. Without that, a freshly-created
                // empty scrap (.normal + empty) would match isSafelyEmpty and be deleted.
                if let lastScrap = scraps.last, isSafelyEmpty(lastScrap) {
                    // Delete the old empty scrap before creating new one
                    await deleteScrap(lastScrap)
                }

                // Create new scrap and wait for it to complete
                if let newScrap = await createNewScrap() {
                    focus(on: newScrap)
                }
            } else if scraps.isEmpty {
                // No scraps at all - create first one
                if let newScrap = await createNewScrap() {
                    focus(on: newScrap)
                }
            } else {
                // Quick return - focus latest scrap
                focusLatestScrap()
            }

            // Step 3: Mark initialization as complete
            isInitialLoad = false
            isReady = true
        }
    }

    // Returns sorted scrap file URLs (oldest first), creating the Documents directory if needed.
    // Returns nil on error, empty array if no scraps exist yet.
    // All file ops on the iCloud container go through NSFileCoordinator so the iCloud
    // daemon sees a consistent view and so we don't race with in-flight syncs from other devices.
    // Async because NSFileCoordinator.coordinate(...) blocks the calling thread until the
    // writer lock is granted — holding that on the main actor freezes the UI when another
    // device is mid-sync. The coordinate helpers hop to a background queue.
    private func enumeratedScrapFiles() async throws -> [URL]? {
        guard let documentsURL = documentsDirectoryURL else {
            print("Error: Could not get iCloud documents directory URL")
            return nil
        }

        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            // Default options ([]) — .forReplacing would imply overwrite semantics to other
            // presenters, which is wrong for create-if-missing.
            try await Self.coordinateWrite(at: documentsURL, options: []) { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }

        let contents: [URL] = try await Self.coordinateRead(at: documentsURL, options: []) { url in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
        }
        return try await normalizeLegacyScrapFiles(in: contents)
    }

    // filePresenter is nil because the owning TextDocument (a UIDocument) is already
    // registered as presenter for its own file and receives coordination callbacks directly.
    // For a DocumentManager-initiated delete/rename of a file that is open in-process, this
    // means the coordinator still notifies the document — accepted here to keep the helper
    // call-site-agnostic rather than threading the owning document through every path.
    private nonisolated static func coordinateRead<T: Sendable>(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions,
        _ body: @Sendable @escaping (URL) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordError: NSError?
                var result: Result<T, Error>?
                coordinator.coordinate(readingItemAt: url, options: options, error: &coordError) { coordinatedURL in
                    result = Result { try body(coordinatedURL) }
                }
                if let coordError {
                    continuation.resume(throwing: coordError)
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    private nonisolated static func coordinateWrite(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ body: @Sendable @escaping (URL) throws -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordError: NSError?
                var thrown: Error?
                coordinator.coordinate(writingItemAt: url, options: options, error: &coordError) { coordinatedURL in
                    do { try body(coordinatedURL) } catch { thrown = error }
                }
                if let coordError {
                    continuation.resume(throwing: coordError)
                } else if let thrown {
                    continuation.resume(throwing: thrown)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private nonisolated static func coordinateMove(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let coordinator = NSFileCoordinator(filePresenter: nil)
                var coordError: NSError?
                var thrown: Error?
                coordinator.coordinate(
                    writingItemAt: source, options: .forMoving,
                    writingItemAt: destination, options: .forReplacing,
                    error: &coordError
                ) { src, dst in
                    do {
                        try FileManager.default.moveItem(at: src, to: dst)
                        coordinator.item(at: src, didMoveTo: dst)
                    } catch {
                        thrown = error
                    }
                }
                if let coordError {
                    continuation.resume(throwing: coordError)
                } else if let thrown {
                    continuation.resume(throwing: thrown)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // Two-phase load used only at init: opens the latest scrap first so the UI becomes
    // interactive immediately, then loads older scraps in the background.
    private func loadScrapsInitial() async {
        do {
            guard let scrapFiles = try await enumeratedScrapFiles(), !scrapFiles.isEmpty else { return }

            // Filenames encode the timestamp, so descending lexicographic order = latest first
            let sortedFiles = scrapFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }

            // Phase 1: open the latest scrap immediately so the panel and keyboard appear
            if let latestFile = sortedFiles.first {
                let filename = latestFile.lastPathComponent
                if let timestamp = Scrap.parseTimestamp(from: filename) {
                    let document = TextDocument(fileURL: latestFile)
                    let scrap = Scrap(timestamp: timestamp, filename: filename, document: document)
                    let success = await withCheckedContinuation { continuation in
                        document.open { continuation.resume(returning: $0) }
                    }
                    if success {
                        attachObserver(to: document)
                        scraps = [scrap]
                        focusLatestScrap()
                    } else {
                        print("Error: Failed to open latest scrap: \(filename)")
                    }
                }
            }

            // Phase 2: open remaining scraps concurrently in the background
            let otherFiles = Array(sortedFiles.dropFirst())
            guard !otherFiles.isEmpty else { return }

            let otherScraps = await withTaskGroup(of: (Scrap, Bool).self, returning: [Scrap].self) { group in
                for fileURL in otherFiles {
                    let filename = fileURL.lastPathComponent
                    guard let timestamp = Scrap.parseTimestamp(from: filename) else { continue }
                    let document = TextDocument(fileURL: fileURL)
                    let scrap = Scrap(timestamp: timestamp, filename: filename, document: document)
                    group.addTask {
                        let success = await withCheckedContinuation { continuation in
                            document.open { continuation.resume(returning: $0) }
                        }
                        return (scrap, success)
                    }
                }
                var results: [Scrap] = []
                for await (scrap, success) in group {
                    if success { results.append(scrap) }
                    else { print("Error: Failed to open scrap: \(scrap.filename)") }
                }
                return results
            }

            // Between Phase 1 completing and Phase 2 finishing, `scraps` may have been
            // mutated by on-demand creation, deletion, or a full `replaceLoadedScraps`.
            // Diff by filename and drop anything already present to avoid duplicate
            // entries + leaked TextDocuments. Close the duplicates so UIDocument's
            // internal file presenter is unregistered.
            let existingFilenames = Set(scraps.map(\.filename))
            var newScraps: [Scrap] = []
            newScraps.reserveCapacity(otherScraps.count)
            for scrap in otherScraps {
                if existingFilenames.contains(scrap.filename) {
                    // Safe to discard: this duplicate was opened in Phase 2 but never had an observer attached and is not in `scraps`, so no user edits can have landed on it.
                    scrap.document.close { _ in }
                } else {
                    newScraps.append(scrap)
                }
            }
            guard !newScraps.isEmpty else { return }

            for scrap in newScraps { attachObserver(to: scrap.document) }
            // Merge and re-sort by timestamp — Phase 2 items are usually older than
            // whatever was loaded in Phase 1, but on-demand-created scraps may have
            // landed in the meantime, so the full sort is the only safe assumption.
            scraps.append(contentsOf: newScraps)
            scraps.sort { $0.timestamp < $1.timestamp }

        } catch {
            print("Error enumerating scrap files: \(error)")
        }
    }

    private func loadScraps() async {
        do {
            guard let scrapFiles = try await enumeratedScrapFiles(), !scrapFiles.isEmpty else { return }

            // Open all documents concurrently
            let loadedScraps = await withTaskGroup(of: (Scrap, Bool).self, returning: [Scrap].self) { group in
                for fileURL in scrapFiles {
                    let filename = fileURL.lastPathComponent

                    guard let timestamp = Scrap.parseTimestamp(from: filename) else {
                        print("Warning: Could not parse timestamp from filename: \(filename)")
                        continue
                    }

                    let document = TextDocument(fileURL: fileURL)
                    let scrap = Scrap(timestamp: timestamp, filename: filename, document: document)

                    group.addTask {
                        let success = await withCheckedContinuation { continuation in
                            document.open { success in
                                continuation.resume(returning: success)
                            }
                        }
                        return (scrap, success)
                    }
                }

                // Collect results into array
                var results: [Scrap] = []
                for await (scrap, success) in group {
                    if success {
                        results.append(scrap)
                    } else {
                        print("Error: Failed to open scrap: \(scrap.filename)")
                    }
                }
                return results
            }

            await replaceLoadedScraps(with: loadedScraps)
        } catch {
            print("Error enumerating scrap files: \(error)")
        }
    }

    @discardableResult
    func createNewScrap() async -> Scrap? {
        guard let documentsURL = documentsDirectoryURL else {
            print("Error: Could not get documents directory URL")
            return nil
        }

        // Filenames encode to second precision, so two creations inside the same second
        // (rapid new-scrap-on-demand, or on-demand creation racing the day-boundary
        // check) would collide. Bump the timestamp one second at a time until we find
        // an unused slot; this preserves chronological sort order without inventing a
        // new filename scheme. Also guard against an in-memory Scrap already holding
        // the same id so we don't re-open a scrap that's mid-delete.
        // TODO: Two devices creating scraps in the same second remain possible; that
        // collision is out of scope here and relies on iCloud conflict resolution.
        let existingFilenames = Set(scraps.map(\.filename))
        var timestamp = Date()
        var filename = Scrap.generateFilename(for: timestamp)
        var fileURL = documentsURL.appendingPathComponent(filename)
        while true {
            let inMemoryCollision = existingFilenames.contains(filename)
            let onDiskCollision = inMemoryCollision ? false : await coordinatedFileExists(at: fileURL)
            if !inMemoryCollision && !onDiskCollision { break }
            timestamp = timestamp.addingTimeInterval(1)
            filename = Scrap.generateFilename(for: timestamp)
            fileURL = documentsURL.appendingPathComponent(filename)
        }
        let document = TextDocument(fileURL: fileURL)
        let scrap = Scrap(timestamp: timestamp, filename: filename, document: document)

        // Publish the placeholder before the async save so a concurrent createNewScrap
        // sees this filename in `existingFilenames` and picks the next second instead
        // of racing the same stale set. On save failure we remove it below.
        self.scraps.append(scrap)
        self.scraps.sort { $0.timestamp < $1.timestamp }

        let success = await withCheckedContinuation { continuation in
            document.save(to: fileURL, for: .forCreating) { success in
                continuation.resume(returning: success)
            }
        }

        if success {
            attachObserver(to: document)
            return scrap
        } else {
            print("Error: Failed to create new scrap")
            self.scraps.removeAll { $0.filename == filename }
            return nil
        }
    }

    // Best-effort coordinated existence probe: lets iCloud settle any in-flight
    // rename/create on this URL before we decide the slot is free. Falls back to
    // a direct check on coordinator error so we never block scrap creation.
    private func coordinatedFileExists(at url: URL) async -> Bool {
        do {
            return try await Self.coordinateRead(at: url, options: []) { coordinatedURL in
                FileManager.default.fileExists(atPath: coordinatedURL.path)
            }
        } catch {
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    func saveLastCloseTime() {
        // Only run once per background event
        guard !hasBackgrounded else { return }
        hasBackgrounded = true
    }

    func resetBackgroundFlag() {
        hasBackgrounded = false
    }

    private func shouldCreateNewScrap() -> Bool {
        guard let latestScrap = scraps.last else {
            return false
        }

        // Read Calendar.current at the call site, not at init. A DocumentManager
        // instance can outlive a timezone change (travel, DST) or a locale change
        // (first-day-of-week); a cached Calendar would then compare against the
        // wrong day boundary and either spuriously create a new scrap or skip
        // creating one that's actually warranted. Using local-calendar
        // `isSameDay` here aligns with how a human thinks about "today" — the
        // UTC-encoded filename is for stable, collision-free sorting only.
        return Calendar.current.isDate(latestScrap.timestamp, inSameDayAs: Date()) == false
    }


    func textDidChange(for scrap: Scrap, newText: String) {
        scrap.document.updateText(newText)

        // Save immediately (UIDocument is async already)
        saveDocument(scrap)
    }

    func saveDocument(_ scrap: Scrap) {
        scrap.document.save(to: scrap.document.fileURL, for: .forOverwriting) { success in
            if !success {
                print("Error: Failed to save scrap: \(scrap.filename)")
            } else {
                Task { @MainActor in
                    self.scheduleWidgetReload()
                }
            }
        }
    }

    func beginBackgroundSaveBarrier() {
        let app = UIApplication.shared
        // End any previously-outstanding task first so we only ever hold one.
        if backgroundSaveTaskID != .invalid {
            app.endBackgroundTask(backgroundSaveTaskID)
            backgroundSaveTaskID = .invalid
        }
        backgroundSaveTaskID = app.beginBackgroundTask(withName: "SaveAllScraps") { [weak self] in
            guard let self else { return }
            if self.backgroundSaveTaskID != .invalid {
                app.endBackgroundTask(self.backgroundSaveTaskID)
                self.backgroundSaveTaskID = .invalid
            }
        }
        saveAllDocuments { [weak self] in
            guard let self else { return }
            if self.backgroundSaveTaskID != .invalid {
                app.endBackgroundTask(self.backgroundSaveTaskID)
                self.backgroundSaveTaskID = .invalid
            }
        }
    }

    func saveAllDocuments(completion: (@MainActor @Sendable () -> Void)? = nil) {
        // Save all scraps (called when app backgrounds). Takes a completion so the
        // caller can hold a UIBackgroundTask open until every async UIDocument.save
        // has actually written to disk — without this, the process can exit on
        // Cmd+Q before the last keystroke is persisted.
        guard !scraps.isEmpty else {
            completion?()
            return
        }

        let group = DispatchGroup()
        for scrap in scraps {
            group.enter()
            scrap.document.save(to: scrap.document.fileURL, for: .forOverwriting) { success in
                if !success {
                    print("Error: Failed to save scrap: \(scrap.filename)")
                }
                group.leave()
            }
        }

        // Watchdog: if a UIDocument.save never invokes its completion (document in a
        // bad state, coordinator deadlock), release the barrier anyway so we don't
        // sit on the background task until the OS kills us (~30s).
        let fired = OSAllocatedUnfairLock(initialState: false)
        let fire: @MainActor @Sendable () -> Void = {
            let shouldRun = fired.withLock { already -> Bool in
                guard !already else { return false }
                already = true
                return true
            }
            if shouldRun {
                WidgetCenter.shared.reloadTimelines(ofKind: "LatestScrapWidget")
                completion?()
            }
        }

        group.notify(queue: .main) {
            // notify(queue: .main) lands on the main *thread* but not the main
            // *actor*; assumeIsolated bridges that for Swift 6 isolation checking.
            MainActor.assumeIsolated { fire() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            let wasStuck = fired.withLock { $0 == false }
            if wasStuck {
                print("Warning: saveAllDocuments watchdog fired after 20s — at least one save did not complete")
            }
            MainActor.assumeIsolated { fire() }
        }
    }

    private func scheduleWidgetReload() {
        widgetReloadWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "LatestScrapWidget")
        }
        widgetReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    private func deleteScrap(_ scrap: Scrap) async {
        removeObserver(for: scrap.document)

        // Close and delete the document
        let success = await withCheckedContinuation { continuation in
            scrap.document.close { success in
                continuation.resume(returning: success)
            }
        }

        if success {
            do {
                try await Self.coordinateWrite(at: scrap.document.fileURL, options: .forDeleting) { url in
                    try FileManager.default.removeItem(at: url)
                }

                // Remove from array
                self.scraps.removeAll { $0.id == scrap.id }
            } catch {
                print("Error deleting scrap file: \(error)")
            }
        }
    }

    private func replaceLoadedScraps(with loadedScraps: [Scrap]) async {
        let currentIDs = Set(scraps.map { $0.id })
        let loadedIDs = Set(loadedScraps.map { $0.id })

        let addedScraps = loadedScraps
            .filter { !currentIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
        let removedScraps = scraps.filter { !loadedIDs.contains($0.id) }
        // Freshly opened documents for scraps that already exist — close them after the diff.
        let duplicateScraps = loadedScraps.filter { currentIDs.contains($0.id) }

        for scrap in addedScraps { attachObserver(to: scrap.document) }

        scraps.removeAll { !loadedIDs.contains($0.id) }
        for newScrap in addedScraps {
            if let idx = scraps.firstIndex(where: { $0.timestamp > newScrap.timestamp }) {
                scraps.insert(newScrap, at: idx)
            } else {
                scraps.append(newScrap)
            }
        }

        await cleanupDocuments(for: removedScraps + duplicateScraps)
    }

    private func cleanupDocuments(for scraps: [Scrap]) async {
        for scrap in scraps {
            removeObserver(for: scrap.document)

            let document = scrap.document
            guard document.documentState.contains(.closed) == false else { continue }

            await withCheckedContinuation { continuation in
                document.close { _ in
                    continuation.resume()
                }
            }
        }
    }

    private func attachObserver(to document: TextDocument) {
        let key = ObjectIdentifier(document)

        guard documentObservers[key] == nil else { return }

        let observer = NotificationCenter.default.addObserver(
            forName: UIDocument.stateChangedNotification,
            object: document,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleDocumentStateChanged(notification)
            }
        }

        documentObservers[key] = observer
    }

    private func removeObserver(for document: TextDocument) {
        let key = ObjectIdentifier(document)

        guard let observer = documentObservers.removeValue(forKey: key) else { return }
        NotificationCenter.default.removeObserver(observer)
    }

    // Note: the outer directory read lock from enumeratedScrapFiles() is dropped before the
    // per-file move locks below are taken. A remote delete/rename slipping in between would
    // make moveItem throw, which we log and skip. Legacy-filename normalisation is a
    // one-shot migration, so per-file best-effort is acceptable rather than holding a
    // directory-wide writer lock across every move.
    private func normalizeLegacyScrapFiles(in contents: [URL]) async throws -> [URL] {
        var normalizedFiles: [URL] = []

        for fileURL in contents where fileURL.lastPathComponent.hasPrefix("scrap-") && fileURL.lastPathComponent.hasSuffix(".txt") {
            guard Scrap.isLegacyFilename(fileURL.lastPathComponent) else {
                normalizedFiles.append(fileURL)
                continue
            }

            guard let legacyTimestamp = Scrap.parseTimestamp(from: fileURL.lastPathComponent) else {
                normalizedFiles.append(fileURL)
                continue
            }

            let normalizedURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(Scrap.generateFilename(for: legacyTimestamp))

            guard normalizedURL != fileURL else {
                normalizedFiles.append(fileURL)
                continue
            }

            guard FileManager.default.fileExists(atPath: normalizedURL.path) == false else {
                print("Warning: Skipping scrap filename normalization because destination exists: \(normalizedURL.lastPathComponent)")
                normalizedFiles.append(fileURL)
                continue
            }

            do {
                try await Self.coordinateMove(from: fileURL, to: normalizedURL)
                normalizedFiles.append(normalizedURL)
            } catch {
                print("Warning: Failed to normalize legacy scrap filename \(fileURL.lastPathComponent): \(error)")
                normalizedFiles.append(fileURL)
            }
        }

        return normalizedFiles
    }

    // Hops off the main actor for the syscall and assigns the result back on
    // main. Callable from init and from identity-change notifications.
    private func probeUbiquityAvailabilityAsync() async {
        let url = await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
        ubiquityContainerURL = url
        iCloudAvailable = url != nil
    }

    private func probeUbiquityAvailability() {
        Task { await probeUbiquityAvailabilityAsync() }
    }

    func checkForUpdates() {
        // Skip if we're still doing the initial load
        guard !isInitialLoad else { return }

        Task {
            // Re-probe on foreground in case the user toggled iCloud Drive for
            // Scraps in Settings while the app was backgrounded.
            await probeUbiquityAvailabilityAsync()
            guard iCloudAvailable else { return }

            await loadScraps()

            guard shouldCreateNewScrap() else {
                focusLatestScrap()
                return
            }

            if let lastScrap = scraps.last, isSafelyEmpty(lastScrap) {
                await deleteScrap(lastScrap)
            }

            if let newScrap = await createNewScrap() {
                focus(on: newScrap)
            }
        }
    }

    // A scrap is safely empty only if its text is blank AND the document is not
    // currently transferring, locked, or in conflict. While iCloud is still
    // downloading or merging content, text can appear as "" even though a non-empty
    // version is about to arrive — deleting in that window would destroy the
    // incoming content. .savingError is deliberately not checked: a save failure
    // shouldn't block cleanup of an otherwise-empty scrap.
    //
    // Residual race: a download can still begin between this check and deleteScrap
    // completing. Tolerable because deleteScrap is file-coordinated and iCloud will
    // re-materialise server-held files via the conflict-resolution path if needed.
    private func isSafelyEmpty(_ scrap: Scrap) -> Bool {
        let state = scrap.document.documentState
        guard !state.contains(.progressAvailable),
              !state.contains(.editingDisabled),
              !state.contains(.inConflict) else {
            return false
        }
        return scrap.document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    func createNewScrapOnDemand() async -> Scrap? {
        guard let latestScrap = scraps.last else {
            let newScrap = await createNewScrap()
            if let newScrap {
                focus(on: newScrap)
            }
            return newScrap
        }

        // If the latest scrap is safely empty, reuse it rather than create another.
        // Using isSafelyEmpty here (not a raw text-only check) avoids handing the
        // user an apparently-blank scrap that is actually mid-download — content
        // would pop in unexpectedly moments later.
        guard !isSafelyEmpty(latestScrap) else {
            focus(on: latestScrap)
            return nil
        }

        let newScrap = await createNewScrap()
        if let newScrap {
            focus(on: newScrap)
        }
        return newScrap
    }

    func focusLatestScrap() {
        guard let latestScrap = scraps.last else {
            focusedScrapID = nil
            focusedScrapFilename = nil
            return
        }

        focus(on: latestScrap)
    }

    private func focus(on scrap: Scrap) {
        guard focusedScrapID != scrap.id || focusedScrapFilename != scrap.filename else { return }
        focusedScrapID = scrap.id
        focusedScrapFilename = scrap.filename
    }

    // Shared focus setter for UI callbacks (editor focus, preview tap). Writes to
    // UserDefaults only once initialisation completes so an early focus event during
    // load doesn't overwrite the persisted last-focused filename.
    func setFocusedScrap(id: String, filename: String, tapLocation: CGPoint? = nil) {
        pendingFocusTapLocation = tapLocation
        focusedScrapID = id
        focusedScrapFilename = filename
        if isReady {
            UserDefaults.standard.set(filename, forKey: "lastFocusedScrapFilename")
        }
    }

    // Tap point in the preview card's local coordinate space, consumed once the
    // editor takes first responder so the caret lands where the user tapped rather
    // than at the end of the scrap. Transient — cleared after use.
    var pendingFocusTapLocation: CGPoint?

    private func handleDocumentStateChanged(_ notification: Notification) {
        guard let document = notification.object as? TextDocument else { return }

        if document.documentState.contains(.inConflict) {
            // Conflict resolution: last-writer-wins strategy
            // UIDocument on iOS does not auto-resolve conflicts - we must handle them manually
            // iCloud automatically chooses the latest modification as currentVersion
            do {
                let url = document.fileURL

                // Get conflict versions BEFORE removing (needed to mark them resolved)
                let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []

                // Remove all non-current versions from iCloud storage
                try NSFileVersion.removeOtherVersionsOfItem(at: url)

                // Mark ALL conflict versions as resolved (prevents quota consumption)
                for version in conflictVersions {
                    version.isResolved = true
                }

                // Mark current version as resolved (belt-and-suspenders)
                if let currentVersion = NSFileVersion.currentVersionOfItem(at: url) {
                    currentVersion.isResolved = true
                }

                if !conflictVersions.isEmpty {
                    print("Resolved \(conflictVersions.count) conflict version(s) for \(url.lastPathComponent)")
                }
            } catch {
                print("Error resolving conflict: \(error)")
            }
        }

        // Trigger UI update when document changes from another device
        // SwiftUI will observe changes to the document's text property
        if document.documentState.contains(.editingDisabled) == false {
            // Force SwiftUI to refresh by triggering objectWillChange
            // Already on main actor, no dispatch needed
            self.objectWillChange.send()
        }
    }

    nonisolated deinit {
        // Remove all observers
        for observer in documentObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        if let ubiquityIdentityObserver {
            NotificationCenter.default.removeObserver(ubiquityIdentityObserver)
        }
    }
}
