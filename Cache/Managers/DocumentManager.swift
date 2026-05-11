import Foundation
import Combine
import UIKit

@MainActor
class DocumentManager: ObservableObject {
    @Published var scraps: [Scrap] = []
    @Published var focusedScrapID: String?
    @Published var focusedScrapFilename: String?
    @Published var isReady = false
    @Published var highlightSettings = HighlightSettings.default
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
    private var foregroundUpdateTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?

    private var hasBackgrounded = false
    private var isInitialLoad = true

    private let fileStore = ScrapFileStore()
    private let widgetReloadScheduler = WidgetReloadScheduler()
    private lazy var saveCoordinator = DocumentSaveCoordinator(widgetReloadScheduler: widgetReloadScheduler)
    private let conflictResolver = ScrapConflictResolver()
    private var resolvingConflictFilenames = Set<String>()

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

            highlightSettings = await fileStore.loadHighlightSettings()

            // Step 1: Load existing scraps, prioritising the latest so the UI is interactive ASAP
            await loadScrapsInitial()

            // Step 2: Backstop for first launch or create failures during initial load.
            if scraps.isEmpty {
                // No scraps at all - create first one
                if let newScrap = await createNewScrap() {
                    focus(on: newScrap)
                }
            } else if shouldCreateNewScrap() {
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

    // Two-phase load used only at init. If the latest on-disk filename is from a
    // prior local day, create today's blank scrap before opening yesterday's file
    // so launch appears to start on the new scrap.
    private func loadScrapsInitial() async {
        do {
            guard let scrapFiles = try await fileStore.enumeratedScrapFiles(), !scrapFiles.isEmpty else { return }

            // Filenames encode the timestamp, so descending lexicographic order = latest first
            let sortedFiles = scrapFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }

            if let latestFile = sortedFiles.first,
               ScrapCreationPolicy.shouldCreateNewScrap(
                   latestTimestamp: Scrap.parseTimestamp(from: latestFile.lastPathComponent)
               ) {
                if let newScrap = await createNewScrap() {
                    focus(on: newScrap)
                }
                await openRemainingInitialScraps(at: sortedFiles)
                return
            }

            // Phase 1: open the latest scrap immediately so the panel and keyboard appear
            if let latestFile = sortedFiles.first,
               let latestScrap = ScrapDocumentLoader.makeScrap(from: latestFile) {
                let success = await ScrapDocumentLoader.openDocument(latestScrap.document)
                if success {
                    attachObserver(to: latestScrap.document)
                    scraps = [latestScrap]
                    focusLatestScrap()
                } else {
                    print("Error: Failed to open latest scrap: \(latestScrap.filename)")
                }
            }

            // Phase 2: open remaining scraps concurrently in the background
            let otherFiles = Array(sortedFiles.dropFirst())
            await openRemainingInitialScraps(at: otherFiles)

        } catch {
            print("Error enumerating scrap files: \(error)")
        }
    }

    private func openRemainingInitialScraps(at fileURLs: [URL]) async {
        guard !fileURLs.isEmpty else { return }

        let otherScraps = await ScrapDocumentLoader.openScraps(at: fileURLs)

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
                await ScrapDocumentLoader.closeDocument(scrap.document)
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
    }

    private func loadScraps() async {
        do {
            guard let scrapFiles = try await fileStore.enumeratedScrapFiles() else { return }
            let diskFilenames = Set(scrapFiles.map(\.lastPathComponent))
            let currentFilenames = Set(scraps.map(\.filename))
            let removedScraps = scraps.filter { !diskFilenames.contains($0.filename) }
            let newFileURLs = scrapFiles.filter { !currentFilenames.contains($0.lastPathComponent) }

            let newScraps = await ScrapDocumentLoader.openScraps(at: newFileURLs)
            for scrap in newScraps { attachObserver(to: scrap.document) }

            scraps = scraps
                .filter { diskFilenames.contains($0.filename) }
                + newScraps
            scraps.sort { $0.timestamp < $1.timestamp }

            await cleanupDocuments(for: removedScraps)
        } catch {
            print("Error enumerating scrap files: \(error)")
        }
    }

    @discardableResult
    func createNewScrap() async -> Scrap? {
        await createNewScrap(initialText: "")
    }

    private func createNewScrap(initialText: String) async -> Scrap? {
        guard let documentsURL = fileStore.documentsDirectoryURL else {
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
            let onDiskCollision = inMemoryCollision ? false : await fileStore.coordinatedFileExists(at: fileURL)
            if !inMemoryCollision && !onDiskCollision { break }
            timestamp = timestamp.addingTimeInterval(1)
            filename = Scrap.generateFilename(for: timestamp)
            fileURL = documentsURL.appendingPathComponent(filename)
        }
        let document = TextDocument(fileURL: fileURL)
        let scrap = Scrap(timestamp: timestamp, filename: filename, document: document)
        if initialText.isEmpty == false {
            document.updateText(initialText)
        }

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
            document.markSaveSucceeded(text: initialText, revision: document.localRevision)
            attachObserver(to: document)
            return scrap
        } else {
            print("Error: Failed to create new scrap")
            self.scraps.removeAll { $0.filename == filename }
            return nil
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
        return ScrapCreationPolicy.shouldCreateNewScrap(latestTimestamp: latestScrap.timestamp)
    }


    func textDidChange(for scrap: Scrap, newText: String) {
        scrap.document.updateText(newText)

        // Save immediately (UIDocument is async already)
        saveDocument(scrap)
    }

    func saveDocument(_ scrap: Scrap) {
        saveCoordinator.saveDocument(scrap)
    }

    func beginBackgroundSaveBarrier() {
        saveCoordinator.beginBackgroundSaveBarrier(for: scraps)
    }

    func saveAllDocuments(completion: (@MainActor @Sendable () -> Void)? = nil) {
        // Save all scraps (called when app backgrounds). Takes a completion so the
        // caller can hold a UIBackgroundTask open until every async UIDocument.save
        // has actually written to disk — without this, the process can exit on
        // Cmd+Q before the last keystroke is persisted.
        saveCoordinator.saveAllDocuments(scraps, completion: completion)
        Task { await saveHighlightSettingsNow() }
    }

    func updateHighlightSettings(_ settings: HighlightSettings) {
        guard highlightSettings != settings else { return }
        highlightSettings = settings
        scheduleHighlightSettingsSave()
    }

    func flushHighlightSettingsSave() {
        Task { await saveHighlightSettingsNow() }
    }

    private func scheduleHighlightSettingsSave() {
        settingsSaveTask?.cancel()
        settingsSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard let self else { return }
            await self.saveHighlightSettingsNow()
        }
    }

    private func saveHighlightSettingsNow() async {
        settingsSaveTask?.cancel()
        settingsSaveTask = nil

        do {
            try await fileStore.saveHighlightSettings(highlightSettings)
            widgetReloadScheduler.scheduleReload()
        } catch {
            print("Warning: Failed to save highlight settings: \(error)")
        }
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
                try await fileStore.deleteFile(at: scrap.document.fileURL)

                // Remove from array
                self.scraps.removeAll { $0.id == scrap.id }
            } catch {
                print("Error deleting scrap file: \(error)")
            }
        }
    }

    private func replaceLoadedScraps(with loadedScraps: [Scrap]) async {
        let reconciliation = ScrapCollectionReconciler.reconcile(
            currentScraps: scraps,
            loadedScraps: loadedScraps
        )

        for scrap in reconciliation.addedScraps { attachObserver(to: scrap.document) }
        scraps = reconciliation.scraps

        await cleanupDocuments(for: reconciliation.removedScraps + reconciliation.duplicateScraps)
    }

    private func cleanupDocuments(for scraps: [Scrap]) async {
        for scrap in scraps {
            removeObserver(for: scrap.document)

            await ScrapDocumentLoader.closeDocument(scrap.document)
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

    // Hops off the main actor for the syscall and assigns the result back on
    // main. Callable from init and from identity-change notifications.
    private func probeUbiquityAvailabilityAsync() async {
        iCloudAvailable = await fileStore.probeUbiquityAvailability()
    }

    private func probeUbiquityAvailability() {
        Task { await probeUbiquityAvailabilityAsync() }
    }

    func checkForUpdates() {
        // Skip if we're still doing the initial load
        guard !isInitialLoad else { return }
        guard foregroundUpdateTask == nil else { return }

        foregroundUpdateTask = Task { [weak self] in
            guard let self else { return }
            defer { foregroundUpdateTask = nil }

            await saveCoordinator.waitForPendingSaveAll()

            // Re-probe on foreground in case the user toggled iCloud Drive for
            // Scraps in Settings while the app was backgrounded.
            await probeUbiquityAvailabilityAsync()
            guard iCloudAvailable else { return }

            highlightSettings = await fileStore.loadHighlightSettings()

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
        return ScrapCreationPolicy.isSafelyEmpty(text: scrap.document.text, documentState: state)
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
            startConflictResolution(for: document)
        }

        // Trigger UI update when document changes from another device
        // SwiftUI will observe changes to the document's text property
        if document.documentState.contains(.editingDisabled) == false {
            // Force SwiftUI to refresh by triggering objectWillChange
            // Already on main actor, no dispatch needed
            self.objectWillChange.send()
        }
    }

    private func startConflictResolution(for document: TextDocument) {
        let filename = document.fileURL.lastPathComponent
        guard resolvingConflictFilenames.insert(filename).inserted else { return }

        Task { [weak self] in
            guard let self else { return }
            await self.resolveConflict(for: document)
            self.resolvingConflictFilenames.remove(filename)
        }
    }

    private func resolveConflict(for document: TextDocument) async {
        guard let scrap = scraps.first(where: { $0.document === document }) else {
            print("Warning: Cannot resolve conflict for unloaded document: \(document.fileURL.lastPathComponent)")
            return
        }

        let url = document.fileURL
        let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard conflictVersions.isEmpty == false else { return }

        print("Resolving sync conflict for \(url.lastPathComponent): \(conflictVersions.count) conflict version(s)")

        switch await conflictResolver.resolution(for: document, conflictVersions: conflictVersions) {
        case .failed:
            print("Error: Failed to read all conflict versions for \(url.lastPathComponent); leaving conflict unresolved")
            return

        case .noOp:
            guard await saveCoordinator.saveDocumentAndWait(scrap) else { return }
            do {
                try markConflictVersionsResolved(at: url, conflictVersions: conflictVersions)
                document.markConflictResolutionCompleted()
            } catch {
                print("Error resolving duplicate conflict versions for \(url.lastPathComponent): \(error)")
            }

        case .merged(let mergedText):
            document.updateText(mergedText)
            guard await saveCoordinator.saveDocumentAndWait(scrap) else { return }
            do {
                try markConflictVersionsResolved(at: url, conflictVersions: conflictVersions)
                document.markConflictResolutionCompleted()
                print("Merged sync conflict for \(url.lastPathComponent)")
            } catch {
                print("Error marking merged conflict resolved for \(url.lastPathComponent): \(error)")
            }

        case .preserveVersions(let versions):
            let preservedText = ScrapConflictPlanner.appendingPreservedConflictSections(
                to: document.text,
                originalFilename: scrap.filename,
                versions: versions
            )
            if preservedText != document.text {
                document.updateText(preservedText)
            }
            guard await saveCoordinator.saveDocumentAndWait(scrap) else { return }

            do {
                try markConflictVersionsResolved(at: url, conflictVersions: conflictVersions)
                document.markConflictResolutionCompleted()
                print("Preserved \(versions.count) sync conflict version(s) inline for \(url.lastPathComponent)")
            } catch {
                print("Error marking preserved conflict resolved for \(url.lastPathComponent): \(error)")
            }
        }
    }

    private func markConflictVersionsResolved(
        at url: URL,
        conflictVersions: [NSFileVersion]
    ) throws {
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
        for version in conflictVersions {
            version.isResolved = true
        }
        NSFileVersion.currentVersionOfItem(at: url)?.isResolved = true
    }

    nonisolated deinit {
        // Remove all observers
        for observer in documentObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        if let ubiquityIdentityObserver {
            NotificationCenter.default.removeObserver(ubiquityIdentityObserver)
        }
        settingsSaveTask?.cancel()
    }
}
