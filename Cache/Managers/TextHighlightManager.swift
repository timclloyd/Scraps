//
//  TextHighlightManager.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//

import SwiftUI

class TextHighlightManager: NSLayoutManager {

    var normalFont: UIFont?

    var searchQuery: String = "" {
        didSet { invalidateSearchHighlights() }
    }
    var activeSearchRange: NSRange? {
        didSet { invalidateSearchHighlights() }
    }

    private var isProcessing = false

    override func processEditing(for textStorage: NSTextStorage,
                               edited editMask: NSTextStorage.EditActions,
                               range newCharRange: NSRange,
                               changeInLength delta: Int,
                               invalidatedRange invalidatedCharRange: NSRange) {
        super.processEditing(for: textStorage,
                            edited: editMask,
                            range: newCharRange,
                            changeInLength: delta,
                            invalidatedRange: invalidatedCharRange)

        // Prevent re-entrant calls during text edits (causes infinite loop)
        guard !isProcessing else { return }
        isProcessing = true

        let text = textStorage.string
        // Process only the edited line(s) for performance (not the entire document).
        // Use mutableString for NSString ops to avoid an extra bridging hop.
        let processRange = textStorage.mutableString.lineRange(for: newCharRange)

        textStorage.beginEditing()

        // Clear styling attributes from edited range, then restore foreground color to the
        // standard label color so struck-through gray doesn't linger if markers are removed
        textStorage.removeAttribute(.backgroundColor, range: processRange)
        textStorage.removeAttribute(.link, range: processRange)
        textStorage.removeAttribute(.underlineStyle, range: processRange)
        textStorage.removeAttribute(.strikethroughStyle, range: processRange)
        textStorage.removeAttribute(.foregroundColor, range: processRange)
        textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: processRange)

        // storageLength is invariant for the duration of this beginEditing/endEditing
        // block — addAttribute does not change length — so caching it is safe.
        let storageLength = textStorage.length

        for keyword in HighlightPatterns.keywords {
            guard let color = HighlightPatterns.highlightColor[keyword.band] else { continue }
            keyword.regex.enumerateMatches(in: text, options: [], range: processRange) { match, _, _ in
                guard let range = match?.range, range.upperBound <= storageLength else { return }
                textStorage.addAttribute(.backgroundColor, value: color, range: range)
            }
        }

        // Detect URLs and make them tappable
        // Only add .link attribute - UITextView handles styling via linkTextAttributes
        if let urlDetector = HighlightPatterns.urlDetector {
            urlDetector.enumerateMatches(in: text, options: [], range: processRange) { match, _, _ in
                guard let match, match.range.upperBound <= storageLength, let url = match.url else { return }
                textStorage.addAttribute(.link, value: url, range: match.range)
            }
        }

        // Apply strikethrough for ~~text~~ patterns, markers and content included.
        HighlightPatterns.strikeRegex?.enumerateMatches(in: text, options: [], range: processRange) { match, _, _ in
            guard let matchRange = match?.range, matchRange.upperBound <= storageLength else { return }
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            textStorage.addAttribute(.foregroundColor, value: Theme.linkColor, range: matchRange)
        }

        textStorage.endEditing()
        isProcessing = false
    }

    private func invalidateSearchHighlights() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullGlyphRange = glyphRange(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        invalidateDisplay(forGlyphRange: fullGlyphRange)
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard !searchQuery.isEmpty, let storage = textStorage, !textContainers.isEmpty else { return }

        let container = textContainers[0]
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let text = storage.mutableString as NSString

        let inactiveColour = Theme.searchHighlightColor
        let activeColour = Theme.searchActiveHighlightColor

        var searchRange = charRange
        while searchRange.length > 0 {
            let matchRange = text.range(of: searchQuery, options: .caseInsensitive, range: searchRange)
            guard matchRange.location != NSNotFound else { break }

            let isActive: Bool
            if let active = activeSearchRange {
                isActive = matchRange.location == active.location && matchRange.length == active.length
            } else {
                isActive = false
            }

            let colour = isActive ? activeColour : inactiveColour
            let matchGlyphRange = glyphRange(forCharacterRange: matchRange, actualCharacterRange: nil)

            enumerateEnclosingRects(
                forGlyphRange: matchGlyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                let adjusted = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1, dy: 0)
                colour.setFill()
                UIBezierPath(roundedRect: adjusted, cornerRadius: 2).fill()
            }

            let next = matchRange.upperBound
            searchRange = NSRange(location: next, length: charRange.upperBound - next)
        }
    }
}
