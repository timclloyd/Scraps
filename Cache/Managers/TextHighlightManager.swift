//
//  TextHighlightManager.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//

import SwiftUI

class TextHighlightManager: NSLayoutManager {
    struct HighlightPattern {
        let pattern: String
        let regex: NSRegularExpression
        let backgroundColor: UIColor

        init?(pattern: String, backgroundColor: UIColor) {
            self.pattern = pattern
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                return nil
            }
            self.regex = regex
            self.backgroundColor = backgroundColor
        }
    }

    // Keywords to highlight for quick visual scanning
    // These capture common intent markers in quick notes/scraps
    // Note: patterns use word boundaries (\b) to avoid partial matches
    let patterns: [HighlightPattern] = [
        HighlightPattern(
            pattern: "\\bidea[a-zA-Z]*",  // "idea", "ideas", etc.
            backgroundColor: Theme.highlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern(
            pattern: "\\bfun\\b",
            backgroundColor: Theme.highlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern(
            pattern: "\\btodo\\b",
            backgroundColor: Theme.highlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern(
            pattern: "\\bremember\\b",
            backgroundColor: Theme.highlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern(
            pattern: "\\bimportant\\b",
            backgroundColor: Theme.highlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern(
            pattern: "\\binteresting\\b",
            backgroundColor: Theme.highlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern(
            pattern: "\\blater\\b",
            backgroundColor: Theme.highlightColor(for: UITraitCollection.current)
        )
    ].compactMap { $0 }

    var normalFont: UIFont?

    var searchQuery: String = "" {
        didSet { invalidateSearchHighlights() }
    }
    var activeSearchRange: NSRange? {
        didSet { invalidateSearchHighlights() }
    }

    private var isProcessing = false
    private let urlDetector: NSDataDetector? = {
        return try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()
    private lazy var strikeRegex: NSRegularExpression? = try? NSRegularExpression(pattern: "~~.+?~~")

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
        // Process only the edited line(s) for performance (not the entire document)
        let processRange = (text as NSString).lineRange(for: newCharRange)

        textStorage.beginEditing()

        // Clear styling attributes from edited range, then restore foreground color to the
        // standard label color so struck-through gray doesn't linger if markers are removed
        textStorage.removeAttribute(.backgroundColor, range: processRange)
        textStorage.removeAttribute(.link, range: processRange)
        textStorage.removeAttribute(.underlineStyle, range: processRange)
        textStorage.removeAttribute(.strikethroughStyle, range: processRange)
        textStorage.removeAttribute(.foregroundColor, range: processRange)
        textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: processRange)

        // Apply keyword highlighting
        for pattern in patterns {
            let matches = pattern.regex.matches(in: text, options: [], range: processRange)
            for match in matches {
                // Validate match is still within text bounds (async edits can invalidate ranges)
                if match.range.location + match.range.length <= textStorage.length {
                    textStorage.addAttribute(.backgroundColor, value: pattern.backgroundColor, range: match.range)
                }
            }
        }

        // Detect URLs and make them tappable
        // Only add .link attribute - UITextView handles styling via linkTextAttributes
        if let urlDetector = urlDetector {
            let urlMatches = urlDetector.matches(in: text, options: [], range: processRange)
            for match in urlMatches {
                guard match.range.location + match.range.length <= textStorage.length,
                      let url = match.url else { continue }

                textStorage.addAttribute(.link, value: url, range: match.range)
            }
        }

        // Apply strikethrough for ~~text~~ patterns, markers and content included.
        strikeRegex?.enumerateMatches(in: text, options: [], range: processRange) { match, _, _ in
            guard let matchRange = match?.range, matchRange.upperBound <= textStorage.length else { return }
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
            textStorage.addAttribute(.foregroundColor, value: UIColor.systemGray3, range: matchRange)
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
        let text = storage.string as NSString

        let inactiveColour = UIColor.systemYellow.withAlphaComponent(0.35)
        let activeColour = UIColor.systemOrange.withAlphaComponent(0.65)

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
