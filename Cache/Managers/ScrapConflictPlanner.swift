import Foundation

enum ScrapConflictPlanner {
    static let preservedConflictMarker = "🔀"
    static let preservedConflictHeaderPrefix = "\(preservedConflictMarker) Sync conflict preserved from "
    static let legacyPreservedConflictHeaderPrefix = "Sync conflict preserved from "

    struct Version: Equatable {
        let text: String
        let sourceDescription: String
        let modificationDate: Date?

        init(text: String, sourceDescription: String, modificationDate: Date? = nil) {
            self.text = text
            self.sourceDescription = sourceDescription
            self.modificationDate = modificationDate
        }
    }

    enum Plan: Equatable {
        case noOp
        case merged(String)
        case preserveVersions([Version])
    }

    static func plan(
        baseText: String?,
        currentText: String,
        conflictVersions: [Version]
    ) -> Plan {
        let uniqueConflicts = uniqueVersions(conflictVersions, excluding: currentText)
        guard uniqueConflicts.isEmpty == false else { return .noOp }

        guard let baseText else {
            return .preserveVersions(uniqueConflicts)
        }

        var mergedText = currentText
        for version in uniqueConflicts {
            if versionIsRepresented(version.text, in: mergedText) {
                continue
            }

            switch TextMerge.conservativeThreeWayMerge(
                base: baseText,
                current: mergedText,
                incoming: version.text
            ) {
            case .merged(let nextText):
                mergedText = nextText
            case .conflict:
                return .preserveVersions(uniqueConflicts)
            }
        }

        return mergedText == currentText ? .noOp : .merged(mergedText)
    }

    private static func uniqueVersions(_ versions: [Version], excluding currentText: String) -> [Version] {
        var seen = Set<String>([currentText])
        var unique: [Version] = []
        for version in versions {
            guard seen.insert(version.text).inserted else { continue }
            guard versionIsRepresented(version.text, in: currentText) == false else { continue }
            unique.append(version)
        }
        return unique
    }

    static func isPreservedConflictCopy(text: String) -> Bool {
        containsPreservedConflict(text: text)
    }

    static func containsPreservedConflict(text: String) -> Bool {
        guard text.contains(preservedConflictHeaderPrefix) || text.contains(legacyPreservedConflictHeaderPrefix) else {
            return false
        }
        return text.hasPrefix("---\n") || text.contains("\n---\n")
    }

    static func appendingPreservedConflictSections(
        to currentText: String,
        originalFilename: String,
        versions: [Version]
    ) -> String {
        versions.reduce(currentText) { text, version in
            guard let preservedBody = preservedBody(for: version),
                  containsPreservedVersion(text: text, preservedBody: preservedBody) == false else {
                return text
            }

            var nextText = text
            if nextText.isEmpty == false {
                if nextText.hasSuffix("\n\n") == false {
                    nextText += nextText.hasSuffix("\n") ? "\n" : "\n\n"
                }
            }
            nextText += preservedConflictSection(originalFilename: originalFilename, version: version)
            return nextText
        }
    }

    static func preservedConflictSection(
        originalFilename _: String,
        version: Version
    ) -> String {
        [
            "---",
            "\(preservedConflictHeaderPrefix)\(version.sourceDescription)",
            "",
            preservedBody(for: version) ?? "",
            "---"
        ].joined(separator: "\n")
    }

    private static func containsPreservedVersion(text: String, preservedBody: String) -> Bool {
        text.contains("\n\(preservedBody)\n---")
    }

    private static func preservedBody(for version: Version) -> String? {
        let body = strippingPreservedConflictSections(from: version.text)
            .trimmingCharacters(in: .newlines)
        return body.isEmpty ? nil : body
    }

    private static func versionIsRepresented(_ versionText: String, in text: String) -> Bool {
        let versionLines = meaningfulLines(in: strippingPreservedConflictSections(from: versionText))
        guard versionLines.isEmpty == false else { return true }

        let currentLines = meaningfulLines(in: strippingPreservedConflictSections(from: text))
        var searchStartIndex = currentLines.startIndex

        for versionLine in versionLines {
            guard let matchIndex = currentLines[searchStartIndex...].firstIndex(of: versionLine) else {
                return false
            }
            searchStartIndex = currentLines.index(after: matchIndex)
        }

        return true
    }

    private static func meaningfulLines(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
    }

    private static func strippingPreservedConflictSections(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0

        while index < lines.count {
            if lines[index] == "---",
               index + 1 < lines.count,
               isPreservedConflictHeader(lines[index + 1]) {
                index += 2
                while index < lines.count, lines[index] != "---" {
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                continue
            }

            output.append(lines[index])
            index += 1
        }

        return output.joined(separator: "\n")
    }

    private static func isPreservedConflictHeader(_ line: String) -> Bool {
        line.hasPrefix(preservedConflictHeaderPrefix) || line.hasPrefix(legacyPreservedConflictHeaderPrefix)
    }
}
