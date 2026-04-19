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
//  URL links are rendered via `.link` attributes on the `AttributedString`; SwiftUI
//  routes taps on those ranges to the `openURL` environment before the outer tap
//  gesture sees them. Non-link taps focus the card and carry the tap location
//  through `DocumentManager.pendingFocusTapLocation` so the editor's caret lands
//  where the user tapped.

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
        .onTapGesture(coordinateSpace: .local) { location in
            documentManager.setFocusedScrap(id: scrap.id, filename: scrap.filename, tapLocation: location)
        }
    }

    // MARK: - Attributed-string builder
    //
    // Mirrors the attribute set applied by `TextHighlightManager.processEditing`
    // so the preview is pixel-equivalent to the editor at rest. Patterns live on
    // `HighlightPatterns` (in `TextHighlightManager.swift`) and are shared across
    // both paths.

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

        for regex in HighlightPatterns.keywordRegexes {
            regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                result.addAttribute(.backgroundColor, value: HighlightPatterns.keywordHighlightColor, range: range)
            }
        }

        HighlightPatterns.strikeRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let matchRange = match?.range else { return }
            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            result.addAttribute(.foregroundColor, value: UIColor.systemGray3, range: matchRange)
        }

        // Match the editor's link styling (set on UITextView via `linkTextAttributes`)
        // so the preview is visually identical. SwiftUI's `Text` dispatches taps on
        // `.link` ranges to the `openURL` environment without consuming the outer
        // gesture for non-link regions.
        HighlightPatterns.urlDetector?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, let url = match.url else { return }
            result.addAttribute(.link, value: url, range: match.range)
            result.addAttribute(.foregroundColor, value: Theme.linkColor, range: match.range)
            result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
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
