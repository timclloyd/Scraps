//
//  ScrapPreviewView.swift
//  Cache
//
//  Read-only preview of a scrap for use in the archive list.
//
//  A full `TextEditorView` (UITextView + NSLayoutManager + regex compilation +
//  autocorrect + gesture recognisers) per archive card is expensive to instantiate
//  and lay out — this caused visible scroll hitches on long scraps. This view
//  replaces the editor for non-focused cards with a SwiftUI `Text` rendering an
//  `AttributedString` pre-decorated with the same keyword highlights, strikethrough,
//  and search matches. Tapping the preview promotes the card back to the full editor
//  by setting `focusedScrapID`.
//
//  URL tap-to-open is intentionally not wired up on the preview — a tap focuses
//  the card, after which the real editor handles link interaction. This keeps the
//  preview cheap.

import SwiftUI

struct ScrapPreviewView: View {
    let scrap: Scrap
    @ObservedObject var document: TextDocument
    let font: UIFont
    var searchQuery: String = ""
    var activeSearchRange: NSRange? = nil

    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        Text(AttributedString(Self.buildAttributedString(
            text: document.text,
            font: font,
            searchQuery: searchQuery,
            activeSearchRange: activeSearchRange
        )))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture {
            documentManager.focusedScrapID = scrap.id
            documentManager.focusedScrapFilename = scrap.filename
            if documentManager.isReady {
                UserDefaults.standard.set(scrap.filename, forKey: "lastFocusedScrapFilename")
            }
        }
    }

    // MARK: - Attributed-string builder
    //
    // Mirrors the attribute set applied by `TextHighlightManager.processEditing`
    // (keyword background, strikethrough + gray, search highlight) so the preview
    // is pixel-equivalent to the editor at rest. Not factored into a shared type
    // because the editor runs inside an `NSLayoutManager` callback with per-line
    // range scoping, while the preview operates on the full string once.

    private static let keywordRegexes: [NSRegularExpression] = {
        let rawPatterns = [
            "\\bidea[a-zA-Z]*",
            "\\bfun\\b",
            "\\btodo\\b",
            "\\bremember\\b",
            "\\bimportant\\b",
            "\\binteresting\\b",
            "\\blater\\b"
        ]
        return rawPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: .caseInsensitive)
        }
    }()

    private static let strikeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "~~.+?~~")
    }()

    private static let keywordHighlightColor: UIColor = UIColor { traits in
        Theme.highlightColor(for: traits)
    }

    private static func buildAttributedString(
        text: String,
        font: UIFont,
        searchQuery: String,
        activeSearchRange: NSRange?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.label
        ])
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return result }

        for regex in keywordRegexes {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                result.addAttribute(.backgroundColor, value: keywordHighlightColor, range: range)
            }
        }

        strikeRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            result.addAttribute(.foregroundColor, value: UIColor.systemGray3, range: matchRange)
        }

        if !searchQuery.isEmpty {
            let ns = text as NSString
            var cursor = NSRange(location: 0, length: fullRange.length)
            while cursor.length > 0 {
                let match = ns.range(of: searchQuery, options: .caseInsensitive, range: cursor)
                guard match.location != NSNotFound else { break }
                let isActive = activeSearchRange.map { $0.location == match.location && $0.length == match.length } ?? false
                let colour = isActive ? Theme.searchActiveHighlightColor : Theme.searchHighlightColor
                result.addAttribute(.backgroundColor, value: colour, range: match)
                let next = match.upperBound
                cursor = NSRange(location: next, length: fullRange.length - next)
            }
        }

        return result
    }
}
