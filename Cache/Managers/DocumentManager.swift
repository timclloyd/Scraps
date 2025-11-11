import Foundation
import Combine
import UIKit

class DocumentManager: ObservableObject {
    @Published var scraps: [Scrap] = []

    private var isLoadingFromDocument = false
    private var documentObservers: [NSObjectProtocol] = []

    // Scrap creation tracking
    private let lastCloseTimeKey = "lastCloseTime"
    private var hasBackgrounded = false

    private var documentsDirectoryURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents")
    }

    init() {
        // Discover and open all scrap documents
        loadScraps { [weak self] in
            // After scraps are loaded, check if we need to create a new one
            self?.checkAndCreateNewScrapIfNeeded()
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
                print("No scraps found, creating first scrap")
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
                            print("Opened scrap: \(filename)")

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

        let filename = Scrap.generateFilename()
        let fileURL = documentsURL.appendingPathComponent(filename)
        let document = TextDocument(fileURL: fileURL)
        let timestamp = Date()
        let scrap = Scrap(timestamp: timestamp, filename: filename, document: document)

        document.save(to: fileURL, for: .forCreating) { [weak self] success in
            if success {
                print("Created new scrap: \(filename)")

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
        print("Saved last close time: \(now)")
    }

    func resetBackgroundFlag() {
        hasBackgrounded = false
    }

    private func checkAndCreateNewScrapIfNeeded() {
        // Check if enough time has elapsed since last close
        let lastCloseTimestamp = UserDefaults.standard.double(forKey: lastCloseTimeKey)

        guard lastCloseTimestamp > 0 else {
            print("No last close time found, not creating new scrap")
            return
        }

        let lastCloseTime = Date(timeIntervalSince1970: lastCloseTimestamp)
        let now = Date()
        let elapsed = now.timeIntervalSince(lastCloseTime)

        print("Time elapsed since last close: \(elapsed) seconds")

        // Check if >60 seconds (1 minute) have elapsed
        guard elapsed > 60 else {
            print("Less than 1 minute elapsed, not creating new scrap")
            return
        }

        // Check if current scrap is non-empty
        guard let currentScrap = scraps.last else {
            print("No scraps exist, not creating new one")
            return
        }

        let currentText = currentScrap.document.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !currentText.isEmpty else {
            print("Current scrap is empty, not creating new scrap")
            return
        }

        // All conditions met - create new scrap
        print("Creating new scrap (>1 minute elapsed and current scrap has content)")
        createNewScrap()
    }

    func textDidChange(for scrap: Scrap, newText: String) {
        guard !isLoadingFromDocument else { return }

        scrap.document.updateText(newText)

        // Save immediately (UIDocument is async already)
        saveDocument(scrap)
    }

    func saveDocument(_ scrap: Scrap) {
        guard !isLoadingFromDocument else { return }

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

    func checkForUpdates() {
        // When app returns to foreground, documents auto-sync via UIDocument
        // No action needed - observers will handle updates
        print("Checking for updates across \(scraps.count) scraps")
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
