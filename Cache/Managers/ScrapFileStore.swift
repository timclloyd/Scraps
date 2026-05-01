import Foundation

@MainActor
final class ScrapFileStore {
    private(set) var ubiquityContainerURL: URL?

    var documentsDirectoryURL: URL? {
        ubiquityContainerURL?.appendingPathComponent("Documents")
    }

    var settingsFileURL: URL? {
        documentsDirectoryURL?.appendingPathComponent("scraps-settings.txt")
    }

    func probeUbiquityAvailability() async -> Bool {
        let url = await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }.value
        ubiquityContainerURL = url
        return url != nil
    }

    // Returns sorted scrap file URLs (oldest first), creating the Documents directory if needed.
    func enumeratedScrapFiles() async throws -> [URL]? {
        guard let documentsURL = documentsDirectoryURL else {
            print("Error: Could not get iCloud documents directory URL")
            return nil
        }

        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try await FileCoordinator.coordinateWrite(at: documentsURL, options: []) { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }

        let contents: [URL] = try await FileCoordinator.coordinateRead(at: documentsURL, options: []) { url in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
        }
        return try await normalizeLegacyScrapFiles(in: contents)
    }

    func coordinatedFileExists(at url: URL) async -> Bool {
        do {
            return try await FileCoordinator.coordinateRead(at: url, options: []) { coordinatedURL in
                FileManager.default.fileExists(atPath: coordinatedURL.path)
            }
        } catch {
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    func deleteFile(at url: URL) async throws {
        try await FileCoordinator.coordinateWrite(at: url, options: .forDeleting) { coordinatedURL in
            try FileManager.default.removeItem(at: coordinatedURL)
        }
    }

    func loadHighlightSettings() async -> HighlightSettings {
        guard let settingsFileURL else { return .default }

        do {
            let exists = try await ensureDocumentsDirectoryAndCheckFileExists(at: settingsFileURL)
            guard exists else {
                try await saveHighlightSettings(.default)
                return .default
            }

            let data = try await FileCoordinator.coordinateRead(at: settingsFileURL, options: []) { url in
                try Data(contentsOf: url)
            }
            guard let text = String(data: data, encoding: .utf8) else { return .default }
            return HighlightSettings(serialized: text)
        } catch {
            print("Warning: Failed to load highlight settings: \(error)")
            return .default
        }
    }

    func saveHighlightSettings(_ settings: HighlightSettings) async throws {
        guard let settingsFileURL else { return }

        _ = try await ensureDocumentsDirectoryAndCheckFileExists(at: settingsFileURL)
        let data = Data(settings.serialized.utf8)
        try await FileCoordinator.coordinateWrite(at: settingsFileURL, options: .forReplacing) { url in
            try data.write(to: url, options: .atomic)
        }
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
                try await FileCoordinator.coordinateMove(from: fileURL, to: normalizedURL)
                normalizedFiles.append(normalizedURL)
            } catch {
                print("Warning: Failed to normalize legacy scrap filename \(fileURL.lastPathComponent): \(error)")
                normalizedFiles.append(fileURL)
            }
        }

        return normalizedFiles
    }

    private func ensureDocumentsDirectoryAndCheckFileExists(at fileURL: URL) async throws -> Bool {
        guard let documentsURL = documentsDirectoryURL else { return false }

        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try await FileCoordinator.coordinateWrite(at: documentsURL, options: []) { url in
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }

        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
