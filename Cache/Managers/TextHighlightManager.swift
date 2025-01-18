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
            self.regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            self.backgroundColor = backgroundColor
        }
    }
    
    let patterns: [HighlightPattern] = [
        HighlightPattern( // Idea
            pattern: "\\bidea[a-zA-Z]*",
            backgroundColor: ThemeColors.dynamicHighlightColor(for: UITraitCollection.current)
        ),
        HighlightPattern( // Fun
            pattern: "\\bfun\\b",
            backgroundColor: ThemeColors.dynamicHighlightColor(for: UITraitCollection.current)
        )
    ]

    private var isProcessing = false
    private let urlDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

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
        let entireRange = NSRange(location: 0, length: text.count)
        
        textStorage.beginEditing()
        
        // Clear existing attributes but keep foreground color
        textStorage.removeAttribute(.backgroundColor, range: entireRange)
        textStorage.removeAttribute(.link, range: entireRange)
        textStorage.removeAttribute(.underlineStyle, range: entireRange)
        
        // Apply pattern highlights
        for pattern in patterns {
            let matches = pattern.regex.matches(in: text, options: [], range: entireRange)
            for match in matches {
                if match.range.location + match.range.length <= textStorage.length {
                    textStorage.addAttribute(.backgroundColor, value: pattern.backgroundColor, range: match.range)
                }
            }
        }
        
        // Detect and style URLs - just add the link attribute
        let urlMatches = urlDetector.matches(in: text, options: [], range: entireRange)
        for match in urlMatches {
            guard match.range.location + match.range.length <= textStorage.length,
                  let url = match.url else { continue }
            
            textStorage.addAttribute(.link, value: url, range: match.range)
        }
        
        textStorage.endEditing()
        isProcessing = false
    }
}
