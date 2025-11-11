import Foundation
import Combine
import UIKit

class DocumentManager: ObservableObject {
    @Published var scraps: [Scrap] = []
    @Published var focusedScrapID: UUID?
    @Published var focusedScrapFilename: String?

    private var documentObservers: [NSObjectProtocol] = []

    // Scrap creation tracking
    private let lastCloseTimeKey = "lastCloseTime"
    private let lastFocusedScrapFilenameKey = "lastFocusedScrapFilename"
    private var hasBackgrounded = false
    private var isInitialLoad = true
    var shouldSaveFocusChanges = false  // Internal so ScrapView can check it

    private var documentsDirectoryURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents")
    }

    init() {
        // Load existing scraps first, then check if we need a new one
        loadScraps { [weak self] in
            guard let self = self else { return }

            if self.shouldCreateNewScrap() {
                // Long absence - create new scrap and focus it
                self.focusedScrapID = self.scraps.last?.id
                self.checkAndCreateNewScrapIfNeeded()
            } else {
                // Quick return or first launch - restore previous focus using filename
                let savedFilename = UserDefaults.standard.string(forKey: self.lastFocusedScrapFilenameKey)

                if let savedFilename = savedFilename,
                   let savedScrap = self.scraps.first(where: { $0.filename == savedFilename }) {
                    // Restore focus to previously focused scrap
                    self.focusedScrapID = savedScrap.id
                    self.focusedScrapFilename = savedFilename
                } else {
                    // First launch or saved scrap no longer exists - focus last scrap
                    self.focusedScrapID = self.scraps.last?.id
                    self.focusedScrapFilename = self.scraps.last?.filename
                }
            }

            self.isInitialLoad = false

            // Enable saving focus changes after initial load completes
            // This prevents auto-focus from overwriting the saved ID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.shouldSaveFocusChanges = true
            }
        }
    }

    private func loadScraps(completion: @escaping () -> Void) {
        guard let documentsURL = documentsDirectoryURL else {
            print("Error: Could not get iCloud documents directory URL")
            completion()
            return
        }

        // Ensure Documents directory exists
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            do {
                try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating Documents directory: \(error)")
                completion()
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
                // No scraps exist, create first one
                createNewScrap()
                completion()
            } else {
                // Load existing scraps
                var loadedScraps: [Scrap] = []
                let group = DispatchGroup()

                for fileURL in scrapFiles {
                    let filename = fileURL.lastPathComponent

                    guard let timestamp = Scrap.parseTimestamp(from: filename) else {
                        print("Warning: Could not parse timestamp from filename: \(filename)")
                        continue
                    }

                    let document = TextDocument(fileURL: fileURL)
                    let scrap = Scrap(timestamp: timestamp, filename: filename, document: document)
                    loadedScraps.append(scrap)

                    // Track document opening
                    group.enter()

                    // Open document
                    document.open { [weak self] success in
                        defer { group.leave() }

                        if success {
                            // Attach observer for state changes
                            let observer = NotificationCenter.default.addObserver(
                                forName: UIDocument.stateChangedNotification,
                                object: document,
                                queue: .main
                            ) { [weak self] notification in
                                self?.handleDocumentStateChanged(notification)
                            }
                            self?.documentObservers.append(observer)
                        } else {
                            print("Error: Failed to open scrap: \(filename)")
                        }
                    }
                }

                // Wait for all documents to open, then update UI
                group.notify(queue: .main) { [weak self] in
                    // Sort by timestamp (oldest first)
                    loadedScraps.sort { $0.timestamp < $1.timestamp }
                    self?.scraps = loadedScraps
                    completion()
                }
            }
        } catch {
            print("Error enumerating scrap files: \(error)")
            // Create first scrap if enumeration fails
            createNewScrap()
            completion()
        }
    }

    func createNewScrap() {
        guard let documentsURL = documentsDirectoryURL else {
            print("Error: Could not get documents directory URL")
            return
        }

        let now = Date()
        let filename = Scrap.generateFilename(for: now)
        let fileURL = documentsURL.appendingPathComponent(filename)
        let document = TextDocument(fileURL: fileURL)
        let scrap = Scrap(timestamp: now, filename: filename, document: document)

        document.save(to: fileURL, for: .forCreating) { [weak self] success in
            if success {
                // Attach observer
                let observer = NotificationCenter.default.addObserver(
                    forName: UIDocument.stateChangedNotification,
                    object: document,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleDocumentStateChanged(notification)
                }
                self?.documentObservers.append(observer)

                DispatchQueue.main.async {
                    self?.scraps.append(scrap)
                    // Sort to ensure chronological order (oldest first)
                    self?.scraps.sort { $0.timestamp < $1.timestamp }
                    // Set focus to the newly created scrap
                    self?.focusedScrapID = scrap.id
                }
            } else {
                print("Error: Failed to create new scrap")
            }
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

    private func checkAndCreateNewScrapIfNeeded() {
        guard shouldCreateNewScrap() else {
            return
        }

        // Create new scrap (even if last one is empty - we'll clean up empty scraps on save)
        createNewScrap()

        // Clear the last close time so we don't create another scrap on the next check
        UserDefaults.standard.removeObject(forKey: lastCloseTimeKey)
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
        // Also clean up empty scraps
        var scrapsToDelete: [Scrap] = []

        for scrap in scraps {
            let trimmedText = scrap.document.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedText.isEmpty {
                // Mark for deletion
                scrapsToDelete.append(scrap)
            } else {
                // Save non-empty scrap
                saveDocument(scrap)
            }
        }

        // Delete empty scraps
        for scrap in scrapsToDelete {
            deleteScrap(scrap)
        }
    }

    private func deleteScrap(_ scrap: Scrap) {
        // Close and delete the document
        scrap.document.close { [weak self] success in
            guard let self = self else { return }

            do {
                try FileManager.default.removeItem(at: scrap.document.fileURL)

                // Remove from array
                DispatchQueue.main.async {
                    self.scraps.removeAll { $0.id == scrap.id }
                }
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
        loadScraps { [weak self] in
            guard let self = self else { return }
            // Focus will be set to new scrap when creation completes
            self.checkAndCreateNewScrapIfNeeded()
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
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }

    deinit {
        // Close all documents
        for scrap in scraps {
            scrap.document.close(completionHandler: nil)
        }

        // Remove all observers
        for observer in documentObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
