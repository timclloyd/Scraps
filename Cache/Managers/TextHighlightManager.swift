//
//  TextHighlightManager.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//

import SwiftUI

extension NSAttributedString.Key {
    static let customURL = NSAttributedString.Key("customURL")
}

class TextHighlightManager: NSLayoutManager {
    struct HighlightPattern {
        let pattern: String
        let regex: NSRegularExpression
        let backgroundColor: UIColor

        init(pattern: String, backgroundColor: UIColor) {
            self.pattern = pattern
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                fatalError("Invalid regex pattern: \(pattern)")
            }
            self.regex = regex
            self.backgroundColor = backgroundColor
        }
    }
    
    let patterns: [HighlightPattern] = [
        HighlightPattern( // Idea
            pattern: "\\bidea[a-zA-Z]*",
            backgroundColor: Theme.dynamicHighlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern( // Fun
            pattern: "\\bfun\\b",
            backgroundColor: Theme.dynamicHighlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern( // Todo
            pattern: "\\btodo\\b",
            backgroundColor: Theme.dynamicHighlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern( // Remember
            pattern: "\\bremember\\b",
            backgroundColor: Theme.dynamicHighlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern( // Important
            pattern: "\\bimportant\\b",
            backgroundColor: Theme.dynamicHighlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern( // Interesting
            pattern: "\\binteresting\\b",
            backgroundColor: Theme.dynamicHighlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern( // Later
            pattern: "\\blater\\b",
            backgroundColor: Theme.dynamicHighlightColor(for: UITraitCollection.current)
        )
    ]

    private var isProcessing = false
    private let urlDetector: NSDataDetector = {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            fatalError("Failed to create URL detector")
        }
        return detector
    }()

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
        
        guard !isProcessing else { return }
        isProcessing = true

        let text = textStorage.string
        let processRange = (text as NSString).lineRange(for: newCharRange)

        textStorage.beginEditing()

        // Clear existing attributes but keep foreground color
        textStorage.removeAttribute(.backgroundColor, range: processRange)
        textStorage.removeAttribute(.link, range: processRange)
        textStorage.removeAttribute(.underlineStyle, range: processRange)

        // Apply pattern highlights
        for pattern in patterns {
            let matches = pattern.regex.matches(in: text, options: [], range: processRange)
            for match in matches {
                if match.range.location + match.range.length <= textStorage.length {
                    textStorage.addAttribute(.backgroundColor, value: pattern.backgroundColor, range: match.range)
                }
            }
        }

        // Detect and style URLs - just add the link attribute
        let urlMatches = urlDetector.matches(in: text, options: [], range: processRange)
        for match in urlMatches {
            guard match.range.location + match.range.length <= textStorage.length,
                  let url = match.url else { continue }
            
            textStorage.addAttribute(.link, value: url, range: match.range)
        }
        
        textStorage.endEditing()
        isProcessing = false
    }
}
