//
//  ContentView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var document = NotesDocument()
    @AppStorage("currentText") private var currentText = ""
    @FocusState private var isFocused: Bool
    @State private var showingDeleteAlert = false
    
    var textSize: CGFloat = 16
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 48
    
    var body: some View {
        VStack(spacing: 0) {
            TextEditorView(
                text: $currentText,
                font: UIFont(name: "JetBrainsMono-Regular", size: textSize) ?? UIFont.systemFont(ofSize: textSize),
                padding: EdgeInsets(
                    top: textSize,
                    leading: horizontalPadding,
                    bottom: verticalPadding,
                    trailing: horizontalPadding
                ),
                onShake: {
                    // Show delete confirmation when shake is detected
                    showingDeleteAlert = true
                }
            )
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onChange(of: currentText) { oldValue, newValue in
                if !newValue.isEmpty {
                    document.addLine(newValue)
                }
            }
            .alert("Clear the cache?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    currentText = ""
                    document.lines.removeAll()
                }
            } message: {
                Text("It's good to forget things sometimes")
            }
        }
    }
}

struct TextEditorView: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont
    var padding: EdgeInsets
    var onShake: () -> Void

    func makeUIView(context: Context) -> ShakeableTextView {
        // Create text storage and layout manager
        let textStorage = NSTextStorage()
        let layoutManager = HighlightLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        // Create text container with proper size
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        // Create text view with our custom text system
        let textView = ShakeableTextView(frame: .zero, textContainer: textContainer)
        textView.isScrollEnabled = true
        textView.font = font
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.keyboardDismissMode = .interactive
        
        // Configure text container for proper width
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(
            top: padding.top,
            left: padding.leading,
            bottom: padding.bottom,
            right: padding.trailing
        )
        
        textView.showsVerticalScrollIndicator = false
        textView.onShake = onShake
        
        return textView
    }
    
    func updateUIView(_ uiView: ShakeableTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            // Process text for highlighting when text is updated
            if let layoutManager = uiView.layoutManager as? HighlightLayoutManager {
                layoutManager.scheduleMatchUpdate(for: text)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextEditorView

        init(_ parent: TextEditorView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            
            // Schedule match finding on background queue
            if let layoutManager = textView.layoutManager as? HighlightLayoutManager {
                layoutManager.scheduleMatchUpdate(for: textView.text)
            }
        }
    }
}

class HighlightLayoutManager: NSLayoutManager {
    struct HighlightPattern {
        let pattern: String
        let regex: NSRegularExpression  // Pre-compile regex
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
    
    func scheduleMatchUpdate(for text: String) {
        // Cancel existing timer
        debounceTimer?.invalidate()
        updateWorkItem?.cancel()
        
        // Skip if text hasn't changed
        guard text != lastProcessedText else { return }
        
        // Create new timer
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.performMatchUpdate(for: text)
        }
    }
    
    private func performMatchUpdate(for text: String) {
        lastProcessedText = text
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Pre-allocate array capacity
            var newMatches = [(range: NSRange, color: UIColor, rects: [CGRect])]()
            newMatches.reserveCapacity(10)  // Adjust based on expected number of matches
            
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
    
    // Memory management
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
                    let paddedRect = highlightRect.insetBy(dx: -1, dy: 0)
                    path.removeAllPoints()
                    // Use the rounded rect initializer and then append that path
                    let roundedRectPath = UIBezierPath(roundedRect: paddedRect, cornerRadius: 3)
                    path.append(roundedRectPath)
                    match.color.setFill()
                    path.fill()
                }
            }
        }
    }
}

class ShakeableTextView: UITextView {
    var onShake: (() -> Void)?
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onShake?()
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }
    
    override func resignFirstResponder() -> Bool {
        // Allow normal resignation of first responder status
        self.inputView = nil
        return super.resignFirstResponder()
    }
}
