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
        let textView = ShakeableTextView()
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
            context.coordinator.scheduleHighlighting(for: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextEditorView
        private var highlightWorkItem: DispatchWorkItem?
        private var lastProcessedText: String = ""

        init(_ parent: TextEditorView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let text = textView.text else { return }
            parent.text = text
            
            // Only schedule update if text has changed
            if lastProcessedText != text {
                lastProcessedText = text
                scheduleHighlighting(for: textView as! ShakeableTextView)
            }
        }
        
        func scheduleHighlighting(for textView: ShakeableTextView) {
            // Cancel any pending highlight operations
            highlightWorkItem?.cancel()
            
            // Create new highlight operation
            let workItem = DispatchWorkItem { [weak self] in
                self?.applyHighlighting(to: textView)
            }
            
            // Store reference to new work item
            highlightWorkItem = workItem
            
            // Schedule the highlighting after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
        }
        
        private func applyHighlighting(to textView: ShakeableTextView) {
            guard let text = textView.text else { return }
            
            // Create attributes on background queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                let attributedString = NSMutableAttributedString(string: text)
                
                // Define the light purple color that works in both light and dark modes
                let highlightColor = UIColor { traitCollection in
                    switch traitCollection.userInterfaceStyle {
                    case .dark:
                        return UIColor(red: 0.4, green: 0.3, blue: 0.6, alpha: 0.3)
                    default:
                        return UIColor(red: 0.85, green: 0.8, blue: 1.0, alpha: 0.3)
                    }
                }
                
                // Set the text color based on the current theme
                let textColor = UIColor.label
                attributedString.addAttribute(.foregroundColor,
                                            value: textColor,
                                            range: NSRange(location: 0, length: text.count))
                
                // Find all occurrences of "idea" (case insensitive)
                let pattern = "\\bidea\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(text.startIndex..., in: text)
                    let matches = regex.matches(in: text, options: [], range: range)
                    
                    // Apply highlighting to each match
                    for match in matches {
                        attributedString.addAttribute(.backgroundColor,
                                                   value: highlightColor,
                                                   range: match.range)
                    }
                }
                
                // Maintain the font
                attributedString.addAttribute(.font,
                                            value: textView.font ?? UIFont.systemFont(ofSize: 16),
                                            range: NSRange(location: 0, length: text.count))
                
                // Update UI on main queue
                DispatchQueue.main.async {
                    // Only update if this is still the current work item
                    if self.highlightWorkItem?.isCancelled == false {
                        // Save selection
                        let selectedRange = textView.selectedRange
                        
                        // Update attributed text
                        textView.attributedText = attributedString
                        
                        // Restore selection
                        textView.selectedRange = selectedRange
                    }
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
}
