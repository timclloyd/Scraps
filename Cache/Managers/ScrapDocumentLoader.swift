import Foundation

@MainActor
enum ScrapDocumentLoader {
    static func makeScrap(from fileURL: URL) -> Scrap? {
        let filename = fileURL.lastPathComponent
        guard let timestamp = Scrap.parseTimestamp(from: filename) else {
            print("Warning: Could not parse timestamp from filename: \(filename)")
            return nil
        }

        let document = TextDocument(fileURL: fileURL)
        return Scrap(timestamp: timestamp, filename: filename, document: document)
    }

    static func openScrap(at fileURL: URL) async -> Scrap? {
        guard let scrap = makeScrap(from: fileURL) else { return nil }
        let success = await openDocument(scrap.document)
        if success {
            return scrap
        } else {
            print("Error: Failed to open scrap: \(scrap.filename)")
            return nil
        }
    }

    static func openScraps(at fileURLs: [URL]) async -> [Scrap] {
        await withTaskGroup(of: Scrap?.self, returning: [Scrap].self) { group in
            for fileURL in fileURLs {
                group.addTask {
                    await openScrap(at: fileURL)
                }
            }

            var results: [Scrap] = []
            for await scrap in group {
                if let scrap {
                    results.append(scrap)
                }
            }
            return results
        }
    }

    static func openDocument(_ document: TextDocument) async -> Bool {
        await withCheckedContinuation { continuation in
            document.open { success in
                continuation.resume(returning: success)
            }
        }
    }

    static func closeDocument(_ document: TextDocument) async {
        guard document.documentState.contains(.closed) == false else { return }

        await withCheckedContinuation { continuation in
            document.close { _ in
                continuation.resume()
            }
        }
    }
}
