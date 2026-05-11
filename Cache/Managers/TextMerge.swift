import Foundation

enum TextMerge {
    enum MergeResult: Equatable {
        case merged(String)
        case conflict
    }

    static func conservativeThreeWayMerge(
        base: String,
        current: String,
        incoming: String
    ) -> MergeResult {
        if current == incoming {
            return .merged(current)
        }
        if current == base {
            return .merged(incoming)
        }
        if incoming == base {
            return .merged(current)
        }

        let baseLines = splitLines(base)
        let currentLines = splitLines(current)
        let incomingLines = splitLines(incoming)

        let currentChange = singleContiguousChange(from: baseLines, to: currentLines)
        let incomingChange = singleContiguousChange(from: baseLines, to: incomingLines)

        guard let currentChange, let incomingChange else {
            return .conflict
        }

        if currentChange.baseRange.isEmpty,
           incomingChange.baseRange.isEmpty,
           currentChange.baseRange.lowerBound == incomingChange.baseRange.lowerBound {
            return mergeConcurrentInsertions(
                baseLines: baseLines,
                currentLines: currentLines,
                incomingLines: incomingLines,
                currentChange: currentChange,
                incomingChange: incomingChange
            )
        }

        guard !currentChange.baseRange.overlaps(incomingChange.baseRange) else {
            return .conflict
        }

        var merged = baseLines
        for change in [currentChange, incomingChange].sorted(by: { $0.baseRange.lowerBound > $1.baseRange.lowerBound }) {
            merged.replaceSubrange(change.baseRange, with: change.replacement)
        }
        return .merged(merged.joined())
    }

    private struct Change {
        let baseRange: Range<Int>
        let replacement: [String]
    }

    private static func splitLines(_ text: String) -> [String] {
        guard text.isEmpty == false else { return [] }
        var lines: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            if let newline = text[start...].firstIndex(of: "\n") {
                let end = text.index(after: newline)
                lines.append(String(text[start..<end]))
                start = end
            } else {
                lines.append(String(text[start..<text.endIndex]))
                break
            }
        }

        return lines
    }

    private static func singleContiguousChange(from base: [String], to edited: [String]) -> Change? {
        if base == edited {
            return Change(baseRange: 0..<0, replacement: [])
        }

        var prefixCount = 0
        while prefixCount < base.count,
              prefixCount < edited.count,
              base[prefixCount] == edited[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < base.count - prefixCount,
              suffixCount < edited.count - prefixCount,
              base[base.count - 1 - suffixCount] == edited[edited.count - 1 - suffixCount] {
            suffixCount += 1
        }

        let baseRange = prefixCount..<(base.count - suffixCount)
        let editedRange = prefixCount..<(edited.count - suffixCount)
        return Change(baseRange: baseRange, replacement: Array(edited[editedRange]))
    }

    private static func mergeConcurrentInsertions(
        baseLines: [String],
        currentLines: [String],
        incomingLines: [String],
        currentChange: Change,
        incomingChange: Change
    ) -> MergeResult {
        guard currentChange.baseRange.lowerBound == incomingChange.baseRange.lowerBound else {
            return .conflict
        }

        if currentChange.replacement == incomingChange.replacement {
            return .merged(currentLines.joined())
        }

        var merged = baseLines
        let combined = currentChange.replacement + incomingChange.replacement
        merged.replaceSubrange(currentChange.baseRange, with: combined)
        return .merged(merged.joined())
    }
}
