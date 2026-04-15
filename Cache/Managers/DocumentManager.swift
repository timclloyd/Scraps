import Foundation
import Combine
import UIKit

@MainActor
class DocumentManager: ObservableObject {
    @Published var scraps: [Scrap] = []
    @Published var focusedScrapID: String?
    @Published var focusedScrapFilename: String?
    @Published var isReady = false

    private var documentObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    private var hasBackgrounded = false
    private var isInitialLoad = true
    private let calendar = Calendar.current

    private var documentsDirectoryURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents")
    }

    init() {
        // Perform async initialization in a task
        Task {
            // Step 1: Load existing scraps, prioritising the latest so the UI is interactive ASAP
            await loadScrapsInitial()

            // Step 2: Check if we need to create a new scrap
            if shouldCreateNewScrap() {
                // Long absence - check if last scrap is empty and replace if needed
                if let lastScrap = scraps.last {
                    let trimmedText = lastScrap.document.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedText.isEmpty {
                        // Delete the old empty scrap before creating new one
                        await deleteScrap(lastScrap)
                    }
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
    private func enumeratedScrapFiles() throws -> [URL]? {
        guard let documentsURL = documentsDirectoryURL else {
            print("Error: Could not get iCloud documents directory URL")
            return nil
        }

        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: nil
        )
        return try normalizeLegacyScrapFiles(in: contents)
    }

    // Two-phase load used only at init: opens the latest scrap first so the UI becomes
    // interactive immediately, then loads older scraps in the background.
    private func loadScrapsInitial() async {
        do {
            guard let scrapFiles = try enumeratedScrapFiles(), !scrapFiles.isEmpty else { return }

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

            for scrap in otherScraps { attachObserver(to: scrap.document) }
            // scraps may already contain latestScrap from Phase 1; merge and re-sort
            scraps = (scraps + otherScraps).sorted { $0.timestamp < $1.timestamp }

        } catch {
            print("Error enumerating scrap files: \(error)")
        }
    }

    private func loadScraps() async {
        do {
            guard let scrapFiles = try enumeratedScrapFiles(), !scrapFiles.isEmpty else { return }

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

        let now = Date()
        let filename = Scrap.generateFilename(for: now)
        let fileURL = documentsURL.appendingPathComponent(filename)
        let document = TextDocument(fileURL: fileURL)
        let scrap = Scrap(timestamp: now, filename: filename, document: document)

        let success = await withCheckedContinuation { continuation in
            document.save(to: fileURL, for: .forCreating) { success in
                continuation.resume(returning: success)
            }
        }

        if success {
            attachObserver(to: document)

            // Update UI
            self.scraps.append(scrap)
            // Sort to ensure chronological order (oldest first)
            self.scraps.sort { $0.timestamp < $1.timestamp }

            return scrap
        } else {
            print("Error: Failed to create new scrap")
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

        return calendar.isDate(latestScrap.timestamp, inSameDayAs: Date()) == false
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
            }
        }
    }

    func saveAllDocuments() {
        // Save all scraps (called when app backgrounds)
        for scrap in scraps {
            saveDocument(scrap)
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
                try FileManager.default.removeItem(at: scrap.document.fileURL)

                // Remove from array
                self.scraps.removeAll { $0.id == scrap.id }
            } catch {
                print("Error deleting scrap file: \(error)")
            }
        }
    }

    private func replaceLoadedScraps(with loadedScraps: [Scrap]) async {
        let previousScraps = scraps

        for scrap in loadedScraps {
            attachObserver(to: scrap.document)
        }

        scraps = loadedScraps.sorted { $0.timestamp < $1.timestamp }

        await cleanupDocuments(for: previousScraps)
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

    private func normalizeLegacyScrapFiles(in contents: [URL]) throws -> [URL] {
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
                try FileManager.default.moveItem(at: fileURL, to: normalizedURL)
                normalizedFiles.append(normalizedURL)
            } catch {
                print("Warning: Failed to normalize legacy scrap filename \(fileURL.lastPathComponent): \(error)")
                normalizedFiles.append(fileURL)
            }
        }

        return normalizedFiles
    }

    func checkForUpdates() {
        // Skip if we're still doing the initial load
        guard !isInitialLoad else { return }

        Task {
            await loadScraps()

            guard shouldCreateNewScrap() else {
                focusLatestScrap()
                return
            }

            if let lastScrap = scraps.last {
                let trimmedText = lastScrap.document.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty {
                    await deleteScrap(lastScrap)
                }
            }

            if let newScrap = await createNewScrap() {
                focus(on: newScrap)
            }
        }
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

        let trimmedText = latestScrap.document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.isEmpty == false else {
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
    }
}
