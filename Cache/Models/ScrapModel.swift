import Foundation

struct Scrap: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let filename: String
    let document: TextDocument

    private static let timestampFormat = "yyyy-MM-dd-HHmmss"
    private static let utcSuffix = "Z"

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

        let isUTCEncoded = timestampString.hasSuffix(utcSuffix)
        let rawTimestampString = isUTCEncoded ? String(timestampString.dropLast()) : timestampString

        guard let parsed = makeDateFormatter(timeZone: isUTCEncoded ? TimeZone(secondsFromGMT: 0)! : TimeZone.current)
            .date(from: rawTimestampString) else {
            print("Warning: Could not parse timestamp '\(timestampString)' from filename: \(filename)")
            return nil
        }

        return parsed
    }

    /// Generate filename for a new scrap with current timestamp
    static func generateFilename(for date: Date = Date()) -> String {
        let timestamp = makeDateFormatter(timeZone: TimeZone(secondsFromGMT: 0)!).string(from: date)
        return "scrap-\(timestamp)\(utcSuffix).txt"
    }

    static func isLegacyFilename(_ filename: String) -> Bool {
        filename.hasPrefix("scrap-") && filename.hasSuffix(".txt") && filename.hasSuffix("\(utcSuffix).txt") == false
    }

    private static func makeDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = timestampFormat
        dateFormatter.timeZone = timeZone
        return dateFormatter
    }
}
