//
//  TextHighlightManager.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//

import SwiftUI

import SwiftUI

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
    
    private lazy var patterns: [HighlightPattern] = [
        HighlightPattern( // Idea
            pattern: "\\bidea[a-zA-Z]*",
            backgroundColor: UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(hue: 205/360, saturation: 0.8, brightness: 1.0, alpha: 0.58)
                default:
                    return UIColor(hue: 205/360, saturation: 0.8, brightness: 1.0, alpha: 0.42)
                }
            }
        ),
        HighlightPattern( // Fun
            pattern: "\\bfun\\b",
            backgroundColor: UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(hue: 142/360, saturation: 0.6, brightness: 1.0, alpha: 0.5)
                default:
                    return UIColor(hue: 142/360, saturation: 0.6, brightness: 1.0, alpha: 0.5)
                }
            }
        )
    ]

    private var updateWorkItem: DispatchWorkItem?
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
        
        // Skip if we're already processing
        guard !isProcessing else { return }
        
        isProcessing = true
        
        let text = textStorage.string
        let entireRange = NSRange(location: 0, length: text.count)
        
        // Begin editing session
        textStorage.beginEditing()
        
        // Clear existing highlights
        textStorage.removeAttribute(.backgroundColor, range: entireRange)
        
        // Apply new highlights immediately
        for pattern in patterns {
            let matches = pattern.regex.matches(in: text, options: [], range: entireRange)
            for match in matches {
                if match.range.location + match.range.length <= textStorage.length {
                    textStorage.addAttribute(.backgroundColor, value: pattern.backgroundColor, range: match.range)
                }
            }
        }
        
        textStorage.endEditing()
        isProcessing = false
    }
    
    deinit {
        updateWorkItem?.cancel()
    }
}
