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
    var highlightKeywords: [HighlightKeyword] = HighlightSettings.default.keywords {
        didSet {
            guard keywordSignature(oldValue) != keywordSignature(highlightKeywords) else { return }
            invalidateHighlightAttributes()
        }
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

        // Process only the edited line(s) for performance (not the entire document).
        // Use mutableString for NSString ops to avoid an extra bridging hop.
        let processRange = textStorage.mutableString.lineRange(for: newCharRange)

        restyle(textStorage, in: processRange)
        isProcessing = false
    }

    private func restyle(_ textStorage: NSTextStorage, in range: NSRange) {
        let text = textStorage.string
        textStorage.beginEditing()

        // Clear styling attributes from edited range, then restore foreground color to the
        // standard label color so struck-through gray doesn't linger if markers are removed
        textStorage.removeAttribute(.backgroundColor, range: range)
        textStorage.removeAttribute(.link, range: range)
        textStorage.removeAttribute(.underlineStyle, range: range)
        textStorage.removeAttribute(.strikethroughStyle, range: range)
        textStorage.removeAttribute(.foregroundColor, range: range)
        textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: range)

        // storageLength is invariant for the duration of this beginEditing/endEditing
        // block — addAttribute does not change length — so caching it is safe.
        let storageLength = textStorage.length
        let strikeRanges = HighlightPatterns.strikeRanges(in: text, range: range)

        for keyword in highlightKeywords {
            guard let color = HighlightPatterns.highlightColor[keyword.band] else { continue }
            keyword.regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let range = match?.range,
                      range.upperBound <= storageLength,
                      !HighlightPatterns.rangeIntersectsStrike(range, strikeRanges: strikeRanges) else { return }
                textStorage.addAttribute(.backgroundColor, value: color, range: range)
            }
        }

        // Detect URLs and make them tappable
        // Only add .link attribute - UITextView handles styling via linkTextAttributes
        if let urlDetector = HighlightPatterns.urlDetector {
            urlDetector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match, match.range.upperBound <= storageLength, let url = match.url else { return }
                textStorage.addAttribute(.link, value: url, range: match.range)
            }
        }

        // Apply strikethrough for ~~text~~ patterns, markers and content included.
        for matchRange in strikeRanges {
            guard matchRange.upperBound <= storageLength else { continue }
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            textStorage.addAttribute(.foregroundColor, value: Theme.linkColor, range: matchRange)
        }

        textStorage.endEditing()
    }

    private func invalidateSearchHighlights() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullGlyphRange = glyphRange(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        invalidateDisplay(forGlyphRange: fullGlyphRange)
    }

    private func invalidateHighlightAttributes() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        guard !isProcessing else { return }
        isProcessing = true
        restyle(storage, in: fullRange)
        isProcessing = false
        invalidateDisplay(forCharacterRange: fullRange)
    }

    private func keywordSignature(_ keywords: [HighlightKeyword]) -> [String] {
        keywords.map { "\($0.band):\($0.pattern)" }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard !searchQuery.isEmpty, let storage = textStorage, !textContainers.isEmpty else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        let container = textContainers[0]
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let text = storage.mutableString as NSString

        let inactiveColour = Theme.searchHighlightColor
        let activeColour = Theme.searchActiveHighlightColor
        let matches = searchMatches(in: text, visibleCharacterRange: charRange)

        var nextGlyphLocation = glyphsToShow.location
        for match in matches {
            let matchGlyphRange = glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            let visibleMatchGlyphRange = NSIntersectionRange(matchGlyphRange, glyphsToShow)
            guard visibleMatchGlyphRange.length > 0 else { continue }

            if nextGlyphLocation < visibleMatchGlyphRange.location {
                let normalRange = NSRange(
                    location: nextGlyphLocation,
                    length: visibleMatchGlyphRange.location - nextGlyphLocation
                )
                super.drawBackground(forGlyphRange: normalRange, at: origin)
            }

            nextGlyphLocation = max(nextGlyphLocation, visibleMatchGlyphRange.upperBound)
        }

        if nextGlyphLocation < glyphsToShow.upperBound {
            let normalRange = NSRange(
                location: nextGlyphLocation,
                length: glyphsToShow.upperBound - nextGlyphLocation
            )
            super.drawBackground(forGlyphRange: normalRange, at: origin)
        }

        for match in matches {
            let colour = match.isActive ? activeColour : inactiveColour
            let matchGlyphRange = glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)

            enumerateEnclosingRects(
                forGlyphRange: matchGlyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { rect, _ in
                let adjusted = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1, dy: 0)
                colour.setFill()
                UIBezierPath(roundedRect: adjusted, cornerRadius: 2).fill()
            }
        }
    }

    private func searchMatches(in text: NSString, visibleCharacterRange charRange: NSRange) -> [(range: NSRange, isActive: Bool)] {
        var matches: [(range: NSRange, isActive: Bool)] = []
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

            matches.append((range: matchRange, isActive: isActive))

            let next = matchRange.upperBound
            searchRange = NSRange(location: next, length: charRange.upperBound - next)
        }
        return matches
    }
}
