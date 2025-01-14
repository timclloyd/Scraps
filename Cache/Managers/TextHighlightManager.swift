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
        let regex: NSRegularExpression // Pre-compile regex
        let color: UIColor
        
        init(pattern: String, color: UIColor) {
            self.pattern = pattern
            self.regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            self.color = color
        }
    }
    
    // Cache patterns at initialization time
    private lazy var patterns: [HighlightPattern] = [
        HighlightPattern( // Idea
            pattern: "\\bidea[a-zA-Z]*",
            color: UIColor { traitCollection in
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
            color: UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return UIColor(hue: 142/360, saturation: 0.6, brightness: 1.0, alpha: 0.5)
                default:
                    return UIColor(hue: 142/360, saturation: 0.6, brightness: 1.0, alpha: 0.5)
                }
            }
        )
    ]
    
    private var cachedMatches: [(range: NSRange, color: UIColor, rects: [CGRect])] = []
    private var lastProcessedText: String = ""
    private var updateWorkItem: DispatchWorkItem?
    
    // Add a debounce timer to prevent too frequent updates
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.1
    
    func scheduleTextHighlight(for text: String) {
        // Cancel existing timer
        debounceTimer?.invalidate()
        updateWorkItem?.cancel()
        
        // Skip if text hasn't changed
        guard text != lastProcessedText else { return }
        
        // Create new timer
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.highlightText(for: text)
        }
    }
    
    private func highlightText(for text: String) {
        lastProcessedText = text
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Pre-allocate array capacity
            var newMatches = [(range: NSRange, color: UIColor, rects: [CGRect])]()
            newMatches.reserveCapacity(20)
            
            let textRange = NSRange(location: 0, length: text.count)
            
            // Process each pattern
            for pattern in self.patterns {
                let matches = pattern.regex.matches(in: text, options: [], range: textRange)
                newMatches.append(contentsOf: matches.map { match in
                    (range: match.range, color: pattern.color, rects: [CGRect]())
                })
            }
            
            // Update cache and invalidate display on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cachedMatches = newMatches
                // Only invalidate the changed regions
                let union = newMatches.reduce(NSRange(location: NSNotFound, length: 0)) { result, match in
                    if result.location == NSNotFound {
                        return match.range
                    }
                    return NSUnionRange(result, match.range)
                }
                if union.location != NSNotFound {
                    let glyphRange = self.glyphRange(forCharacterRange: union, actualCharacterRange: nil)
                    self.invalidateDisplay(forGlyphRange: glyphRange)
                }
            }
        }
        
        updateWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }
    
    deinit {
        updateWorkItem?.cancel()
        debounceTimer?.invalidate()
    }
    
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        guard let textContainer = textContainers.first,
              !cachedMatches.isEmpty else { return }
        
        // Create path once and reuse
        let path = UIBezierPath()
        path.lineWidth = 0
        
        for match in cachedMatches {
            let matchGlyphRange = glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            
            if NSIntersectionRange(matchGlyphRange, glyphsToShow).length > 0 {
                enumerateEnclosingRects(forGlyphRange: matchGlyphRange,
                                      withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                      in: textContainer) { (rect, stop) in
                    let highlightRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                    let paddedRect = highlightRect.insetBy(dx: -1, dy: 1)
                    path.removeAllPoints()
                    // Use the rounded rect initializer and then append that path
                    let roundedRectPath = UIBezierPath(roundedRect: paddedRect, cornerRadius: 0)
                    path.append(roundedRectPath)
                    match.color.setFill()
                    path.fill()
                }
            }
        }
    }
}
