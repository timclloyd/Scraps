import Foundation
import Combine
import UIKit

class DocumentManager: ObservableObject {
    @Published var text: String = ""

    private var document: TextDocument?
    private var saveTimer: Timer?
    private var isLoadingFromDocument = false

    private var documentURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        return documentsURL.appendingPathComponent("scraps.txt")
    }

    init() {
        // Save immediately before app backgrounds or terminates
        // Background sync is not guaranteed, so explicit save is critical
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveBeforeBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        // Check for remote changes when app returns to foreground
        // Ensures user sees latest content from other devices
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkForUpdates),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // One-time migration from old @AppStorage implementation
        migrateFromUserDefaults()

        // Open or create iCloud document
        openDocument()
    }

    private func migrateFromUserDefaults() {
        if let oldText = UserDefaults.standard.string(forKey: "currentText"), !oldText.isEmpty {
            text = oldText
            UserDefaults.standard.removeObject(forKey: "currentText")
            UserDefaults.standard.synchronize()
        }
    }

    private func openDocument() {
        guard let url = documentURL else {
            print("Error: Could not get iCloud document URL")
            return
        }

        // Ensure Documents directory exists
        let documentsURL = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            do {
                try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            } catch {
                print("Error creating Documents directory: \(error)")
                return
            }
        }

        document = TextDocument(fileURL: url)

        document?.open { [weak self] success in
            guard let self = self else { return }

            if success {
                self.isLoadingFromDocument = true
                DispatchQueue.main.async {
                    self.text = self.document?.text ?? ""
                    self.isLoadingFromDocument = false
                }

                // Attach observer after successful open to catch state changes
                // Setting up before open could miss initial state transitions
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.handleDocumentStateChanged),
                    name: UIDocument.stateChangedNotification,
                    object: self.document
                )
            } else {
                print("Error: Failed to open document")
            }
        }
    }

    func textDidChange(_ newText: String) {
        guard !isLoadingFromDocument else { return }

        text = newText

        // Debounced save: wait 2 seconds after user stops typing before saving
        // Reduces unnecessary iCloud writes (each costs battery/bandwidth/quota)
        // Balances data safety with performance
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.saveDocument()
        }
    }

    private func saveDocument() {
        guard let document = document, !isLoadingFromDocument else { return }

        document.updateText(text)

        document.save(to: document.fileURL, for: .forOverwriting) { success in
            if !success {
                print("Error: Failed to save document")
            }
        }
    }

    @objc private func saveBeforeBackground() {
        saveTimer?.invalidate()
        saveDocument()
    }

    @objc private func checkForUpdates() {
        // When app returns to foreground, reload document content
        // UIDocument automatically syncs with iCloud, we just need to update UI
        guard let document = document else { return }

        isLoadingFromDocument = true
        DispatchQueue.main.async { [weak self] in
            self?.text = document.text
            self?.isLoadingFromDocument = false
        }
    }

    @objc private func handleDocumentStateChanged() {
        guard let document = document else { return }

        if document.documentState.contains(.inConflict) {
            // Conflict resolution: last-writer-wins strategy
            // UIDocument on iOS does NOT auto-resolve conflicts - we must handle them manually
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
                    print("Resolved \(conflictVersions.count) conflict version(s)")
                }
            } catch {
                print("Error resolving conflict: \(error)")
            }
        }

        // Update UI when document changes from another device
        // Only update if document is editable (avoid flickering during state transitions)
        if document.documentState.contains(.editingDisabled) == false {
            isLoadingFromDocument = true
            DispatchQueue.main.async { [weak self] in
                self?.text = document.text
                self?.isLoadingFromDocument = false
            }
        }
    }

    deinit {
        saveTimer?.invalidate()
        document?.close(completionHandler: nil)
        NotificationCenter.default.removeObserver(self)
    }
}
