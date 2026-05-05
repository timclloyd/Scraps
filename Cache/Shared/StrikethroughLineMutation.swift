import Foundation

enum StrikethroughLineMutation {
    struct Result {
        let replacement: String
        let caretOffset: Int
    }

    static func isStruck(_ content: String) -> Bool {
        content.hasPrefix("~~") && content.hasSuffix("~~") && content.count > 4
    }

    static func result(for lineText: String, isRightSwipe: Bool) -> Result? {
        let hasTrailingNewline = lineText.hasSuffix("\n")
        let content = hasTrailingNewline ? String(lineText.dropLast()) : lineText
        let suffix = hasTrailingNewline ? "\n" : ""

        guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        let struck = isStruck(content)
        guard isRightSwipe ? !struck : struck else { return nil }

        let newContent: String
        if isRightSwipe {
            newContent = "~~\(content)~~"
        } else {
            newContent = String(content.dropFirst(2).dropLast(2))
        }

        return Result(
            replacement: newContent + suffix,
            caretOffset: newContent.utf16.count
        )
    }
}
