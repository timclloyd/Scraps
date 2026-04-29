import Foundation

final class ScrapFileStore {
    private(set) var ubiquityContainerURL: URL?

    var documentsDirectoryURL: URL? {
        ubiquityContainerURL?.appendingPathComponent("Documents")
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
}
