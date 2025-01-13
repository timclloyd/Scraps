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
    private var cachedMatches: [(range: NSRange, rects: [CGRect])] = []
    private var lastProcessedText: String = ""
    private var updateWorkItem: DispatchWorkItem?
    
    let highlightColor = UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hue: 205 / 360, saturation: 0.8, brightness: 1.0, alpha: 0.58)
        default:
            return UIColor(hue: 205 / 360, saturation: 0.8, brightness: 1.0, alpha: 0.42)
        }
    }
    
    func scheduleMatchUpdate(for text: String) {
        // Cancel any pending updates
        updateWorkItem?.cancel()
        
        // Skip if text hasn't changed
        guard text != lastProcessedText else { return }
        lastProcessedText = text
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Find matches in background
            let pattern = "\\bidea[a-zA-Z]*"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.count))
            let newMatches = matches.map { match in
                (range: match.range, rects: [CGRect]()) // Empty rects to be filled during drawing
            }
            
            // Update cache and invalidate display on main thread
            DispatchQueue.main.async {
                self.cachedMatches = newMatches
                self.invalidateDisplay(forGlyphRange: NSRange(location: 0, length: self.numberOfGlyphs))
            }
        }
        
        updateWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }
    
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        
        guard let textContainer = textContainers.first else { return }
        
        // Draw highlights for cached matches that intersect with the current glyph range
        for match in cachedMatches {
            let matchGlyphRange = glyphRange(forCharacterRange: match.range, actualCharacterRange: nil)
            
            // Check if this match intersects with the glyphs we're supposed to show
            if NSIntersectionRange(matchGlyphRange, glyphsToShow).length > 0 {
                // Get rects for this range of text
                enumerateEnclosingRects(forGlyphRange: matchGlyphRange,
                                      withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                      in: textContainer) { (rect, stop) in
                    // Draw highlight
                    let highlightRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                    let paddedRect = highlightRect.insetBy(dx: -1, dy: 0)
                    self.highlightColor.setFill()
                    UIBezierPath(roundedRect: paddedRect, cornerRadius: 3).fill()
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
    
    override func resignFirstResponder() -> Bool {
        // Keep first responder status for shake detection, but hide keyboard
        self.inputView = UIView()
        return false
    }
    
    override func becomeFirstResponder() -> Bool {
        self.inputView = nil
        return super.becomeFirstResponder()
    }
}
