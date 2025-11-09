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
        // Observe app lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveBeforeBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkForUpdates),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // Migrate from UserDefaults if needed
        migrateFromUserDefaults()

        // Open the document
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

                // Set up automatic conflict resolution
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

        // Invalidate existing timer
        saveTimer?.invalidate()

        // Schedule new save after 2 seconds of inactivity
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
        // UIDocument automatically handles updates when reopened
        // We just need to ensure we're reflecting the latest state
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
            // Handle conflicts: last-writer-wins (choose current version)
            do {
                try NSFileVersion.removeOtherVersionsOfItem(at: document.fileURL)

                if let currentVersion = NSFileVersion.currentVersionOfItem(at: document.fileURL) {
                    currentVersion.isResolved = true
                }
            } catch {
                print("Error resolving conflict: \(error)")
            }
        }

        // Update text if document changed externally
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
