import Foundation

struct Scrap: Identifiable {
    let id: UUID
    let timestamp: Date
    let filename: String
    let document: TextDocument

    init(timestamp: Date, filename: String, document: TextDocument) {
        self.id = UUID()
        self.timestamp = timestamp
        self.filename = filename
        self.document = document
    }

    /// Parse timestamp from filename in format: scrap-YYYY-MM-DD-HHmmss.txt
    static func parseTimestamp(from filename: String) -> Date? {
        // Extract timestamp portion from filename
        // Expected format: scrap-2025-01-11-104153.txt
        guard filename.hasPrefix("scrap-"),
              filename.hasSuffix(".txt") else {
            print("Warning: Invalid scrap filename format: \(filename)")
            return nil
        }

        let timestampString = filename
            .replacingOccurrences(of: "scrap-", with: "")
            .replacingOccurrences(of: ".txt", with: "")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        dateFormatter.timeZone = TimeZone.current

        guard let parsed = dateFormatter.date(from: timestampString) else {
            print("Warning: Could not parse timestamp '\(timestampString)' from filename: \(filename)")
            return nil
        }

        return parsed
    }

    /// Generate filename for a new scrap with current timestamp
    static func generateFilename(for date: Date = Date()) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        dateFormatter.timeZone = TimeZone.current
        let timestamp = dateFormatter.string(from: date)
        return "scrap-\(timestamp).txt"
    }
}
