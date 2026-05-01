import Foundation

struct HighlightSettings: Equatable, Sendable {
    var green: String
    var blue: String
    var red: String

    static let `default` = HighlightSettings(
        green: "idea",
        blue: "todo\nremember",
        red: "important"
    )

    var keywords: [HighlightKeyword] {
        makeKeywords(from: green, band: .positive)
            + makeKeywords(from: blue, band: .neutral)
            + makeKeywords(from: red, band: .negative)
    }

    var serialized: String {
        """
        [green]
        \(green)

        [blue]
        \(blue)

        [red]
        \(red)
        """
    }

    init(green: String, blue: String, red: String) {
        self.green = green
        self.blue = blue
        self.red = red
    }

    init(serialized text: String) {
        var sections: [String: [String]] = [:]
        var currentSection: String?

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).lowercased()
                sections[currentSection!, default: []] = []
            } else if let currentSection {
                sections[currentSection, default: []].append(line)
            }
        }

        self.green = Self.trimStoredSection(sections["green"]) ?? Self.default.green
        self.blue = Self.trimStoredSection(sections["blue"]) ?? Self.default.blue
        self.red = Self.trimStoredSection(sections["red"]) ?? Self.default.red
    }

    private static func trimStoredSection(_ lines: [String]?) -> String? {
        guard var lines else { return nil }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private func makeKeywords(from text: String, band: ValenceBand) -> [HighlightKeyword] {
        text.components(separatedBy: .newlines).compactMap { rawTerm in
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return nil }
            let escaped = NSRegularExpression.escapedPattern(for: term)
            let pattern = "\\b\(escaped)[a-zA-Z]*"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            return HighlightKeyword(pattern: pattern, regex: regex, band: band)
        }
    }
}
