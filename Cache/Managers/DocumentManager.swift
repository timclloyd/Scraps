import Foundation
import Combine
import UIKit

@MainActor
class DocumentManager: ObservableObject {
    @Published var scraps: [Scrap] = []
    @Published var focusedScrapID: UUID?
    @Published var focusedScrapFilename: String?
    @Published var isReady = false

    private var documentObservers: [NSObjectProtocol] = []

    // Scrap creation tracking
    private let lastCloseTimeKey = "lastCloseTime"
    private let lastFocusedScrapFilenameKey = "lastFocusedScrapFilename"
    private var hasBackgrounded = false
    private var isInitialLoad = true

    private var documentsDirectoryURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents")
    }

    init() {
        // Perform async initialization in a task
        Task {
            // Step 1: Load existing scraps
            await loadScraps()

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
                    // Set focus to the newly created scrap
                    focusedScrapID = newScrap.id
                    focusedScrapFilename = newScrap.filename
                }

                // Clear the last close time
                UserDefaults.standard.removeObject(forKey: lastCloseTimeKey)
            } else if scraps.isEmpty {
                // No scraps at all - create first one
                if let newScrap = await createNewScrap() {
                    focusedScrapID = newScrap.id
                    focusedScrapFilename = newScrap.filename
                }
            } else {
                // Quick return - restore previous focus using filename
                let savedFilename = UserDefaults.standard.string(forKey: lastFocusedScrapFilenameKey)

                if let savedFilename = savedFilename,
                   let savedScrap = scraps.first(where: { $0.filename == savedFilename }) {
                    // Restore focus to previously focused scrap
                    focusedScrapID = savedScrap.id
                    focusedScrapFilename = savedFilename
                } else {
                    // First launch or saved scrap no longer exists - focus last scrap
                    focusedScrapID = scraps.last?.id
                    focusedScrapFilename = scraps.last?.filename
                }
            }

            // Step 3: Mark initialization as complete
            isInitialLoad = false
            isReady = true
        }
    }

    private func loadScraps() async {
        guard let documentsURL = documentsDirectoryURL else {
            print("Error: Could not get iCloud documents directory URL")
            return
        }

        // Ensure Documents directory exists
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            do {
                try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating Documents directory: \(error)")
                return
            }
        }

        // Enumerate existing scrap files
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: nil
            )

            let scrapFiles = contents.filter { $0.lastPathComponent.hasPrefix("scrap-") && $0.lastPathComponent.hasSuffix(".txt") }

            if scrapFiles.isEmpty {
                // No scraps exist, will create first one in init
                return
            }

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

            // Attach observers
            for scrap in loadedScraps {
                let observer = NotificationCenter.default.addObserver(
                    forName: UIDocument.stateChangedNotification,
                    object: scrap.document,
                    queue: .main
                ) { [weak self] notification in
                    MainActor.assumeIsolated {
                        self?.handleDocumentStateChanged(notification)
                    }
                }
                self.documentObservers.append(observer)
            }

            // Sort by timestamp (oldest first) and update UI
            self.scraps = loadedScraps.sorted { $0.timestamp < $1.timestamp }
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
            // Attach observer
            let observer = NotificationCenter.default.addObserver(
                forName: UIDocument.stateChangedNotification,
                object: document,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    self?.handleDocumentStateChanged(notification)
                }
            }
            self.documentObservers.append(observer)

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
        // Only save once per background event
        guard !hasBackgrounded else { return }
        hasBackgrounded = true

        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastCloseTimeKey)

        // Save currently focused scrap filename for restoration on quick return
        if let focusedFilename = focusedScrapFilename {
            UserDefaults.standard.set(focusedFilename, forKey: lastFocusedScrapFilenameKey)
        }
    }

    func resetBackgroundFlag() {
        hasBackgrounded = false
    }

    private func shouldCreateNewScrap() -> Bool {
        // Check if enough time has elapsed since last close
        let lastCloseTimestamp = UserDefaults.standard.double(forKey: lastCloseTimeKey)

        guard lastCloseTimestamp > 0 else {
            return false
        }

        let lastCloseTime = Date(timeIntervalSince1970: lastCloseTimestamp)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCloseTime)

        // Check if threshold time has elapsed
        return elapsed > Preferences.newScrapThresholdSeconds
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

    func checkForUpdates() {
        // Skip if we're still doing the initial load
        guard !isInitialLoad else { return }

        // Only reload if enough time has elapsed for a new scrap
        // This avoids unnecessary reloads and view updates on quick app switches
        guard shouldCreateNewScrap() else { return }

        // Reload scraps from disk to catch any changes, then create new scrap
        Task {
            await loadScraps()

            // Check if last scrap is empty and replace if needed
            if let lastScrap = scraps.last {
                let trimmedText = lastScrap.document.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedText.isEmpty {
                    await deleteScrap(lastScrap)
                }
            }

            // Create new scrap
            if let newScrap = await createNewScrap() {
                focusedScrapID = newScrap.id
                focusedScrapFilename = newScrap.filename
            }

            // Clear the last close time
            UserDefaults.standard.removeObject(forKey: lastCloseTimeKey)
        }
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
        // Note: We can't access @MainActor properties like scraps here,
        // so document cleanup should happen elsewhere (e.g., when app backgrounds)
        for observer in documentObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
