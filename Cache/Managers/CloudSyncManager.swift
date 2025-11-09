import Foundation
import Combine
import UIKit

class CloudSyncManager: ObservableObject {
    @Published var text: String = ""

    private var saveTimer: Timer?
    private var metadataQuery: NSMetadataQuery?
    private let fileName = "scraps.txt"
    private var isSyncingFromCloud = false
    private var lastLocalModificationDate: Date?

    private var fileURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        return documentsURL.appendingPathComponent(fileName)
    }

    private var localCacheURL: URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsURL.appendingPathComponent(fileName)
    }

    init() {
        loadInitialContent()
        setupCloudMonitoring()

        // Observe text changes for debounced saving
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveBeforeTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(saveBeforeBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    private func loadInitialContent() {
        // Try to migrate from UserDefaults first
        if let oldText = UserDefaults.standard.string(forKey: "currentText"), !oldText.isEmpty {
            text = oldText
            saveImmediately()
            UserDefaults.standard.removeObject(forKey: "currentText")
            UserDefaults.standard.synchronize()
            return
        }

        // Try to load from iCloud
        if let content = loadFromCloud() {
            text = content
            return
        }

        // Fall back to local cache
        if let content = loadFromLocalCache() {
            text = content
            return
        }

        // Default empty state
        text = ""
    }

    private func loadFromCloud() -> String? {
        guard let url = fileURL else { return nil }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let content = try String(contentsOf: url, encoding: .utf8)
                lastLocalModificationDate = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
                // Also update local cache
                saveToLocalCache(content)
                return content
            }
        } catch {
            print("Error loading from iCloud: \(error)")
        }

        return nil
    }

    private func loadFromLocalCache() -> String? {
        guard let url = localCacheURL else { return nil }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                return try String(contentsOf: url, encoding: .utf8)
            }
        } catch {
            print("Error loading from local cache: \(error)")
        }

        return nil
    }

    private func saveToLocalCache(_ content: String) {
        guard let url = localCacheURL else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Error saving to local cache: \(error)")
        }
    }

    func textDidChange(_ newText: String) {
        text = newText

        // Invalidate existing timer
        saveTimer?.invalidate()

        // Schedule new save after 2 seconds of inactivity
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.saveImmediately()
        }
    }

    private func saveImmediately() {
        guard !isSyncingFromCloud else { return }
        guard let url = fileURL else {
            // If iCloud is not available, save to local cache
            saveToLocalCache(text)
            return
        }

        do {
            // Ensure Documents directory exists
            let documentsURL = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: documentsURL.path) {
                try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            }

            // Save to iCloud
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastLocalModificationDate = Date()

            // Also save to local cache for offline access
            saveToLocalCache(text)
        } catch {
            print("Error saving to iCloud: \(error)")
            // Fall back to local cache on error
            saveToLocalCache(text)
        }
    }

    @objc private func saveBeforeTerminate() {
        saveTimer?.invalidate()
        saveImmediately()
    }

    @objc private func saveBeforeBackground() {
        saveTimer?.invalidate()
        saveImmediately()
    }

    private func setupCloudMonitoring() {
        guard fileURL != nil else { return }

        metadataQuery = NSMetadataQuery()
        guard let query = metadataQuery else { return }

        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )

        query.start()
    }

    @objc private func metadataQueryDidUpdate() {
        handleRemoteUpdate()
    }

    @objc private func metadataQueryDidFinishGathering() {
        handleRemoteUpdate()
    }

    private func handleRemoteUpdate() {
        guard let url = fileURL else { return }

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let remoteModificationDate = attributes[.modificationDate] as? Date

                // Last-writer-wins: only update if remote is newer
                if let remoteDate = remoteModificationDate,
                   let localDate = lastLocalModificationDate,
                   remoteDate > localDate {
                    loadRemoteContent()
                } else if lastLocalModificationDate == nil {
                    // First time seeing this file
                    loadRemoteContent()
                }
            }
        } catch {
            print("Error checking remote file: \(error)")
        }
    }

    private func loadRemoteContent() {
        guard let url = fileURL else { return }

        do {
            isSyncingFromCloud = true
            let content = try String(contentsOf: url, encoding: .utf8)

            DispatchQueue.main.async { [weak self] in
                self?.text = content
                self?.lastLocalModificationDate = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
                self?.saveToLocalCache(content)
                self?.isSyncingFromCloud = false
            }
        } catch {
            print("Error loading remote content: \(error)")
            isSyncingFromCloud = false
        }
    }

    deinit {
        saveTimer?.invalidate()
        metadataQuery?.stop()
        NotificationCenter.default.removeObserver(self)
    }
}
