//
//  UITextViewWrapper.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//
//  SwiftUI wrapper for UITextView to enable:
//  1. Custom TextLayoutManager for real-time syntax highlighting
//  2. Reliable keyboard show/hide behavior (SwiftUI TextEditor has issues)
//  3. Shake gesture detection via CustomTextView

import SwiftUI

struct UITextViewWrapper: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont
    var padding: EdgeInsets
    var onShake: () -> Void
    var onScroll: ((UIScrollView) -> Void)?

    func makeUIView(context: Context) -> CustomTextView {
        let layoutManager = TextHighlightManager()
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        let textStorage = NSTextStorage()
        
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        
        let textView = CustomTextView(frame: .zero, textContainer: textContainer)
        textView.isScrollEnabled = true
        textView.font = font
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.keyboardDismissMode = .none
        textView.showsVerticalScrollIndicator = false
        textView.onShake = onShake
        
        textView.textContainerInset = UIEdgeInsets(
            top: padding.top,
            left: padding.leading,
            bottom: padding.bottom,
            right: padding.trailing
        )
        
        return textView
    }
    
    func updateUIView(_ uiView: CustomTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: UITextViewWrapper

        init(_ parent: UITextViewWrapper) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Auto-scroll to keep cursor visible during keyboard navigation
            // Without this, arrow keys move cursor but view doesn't scroll (poor UX on macOS)
            textView.scrollRangeToVisible(textView.selectedRange)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.onScroll?(scrollView)
        }
    }
}
