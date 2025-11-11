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
    var onScroll: ((UIScrollView) -> Void)? = nil
    var shouldBecomeFirstResponder: Bool = false

    func makeUIView(context: Context) -> CustomTextView {
        let layoutManager = TextHighlightManager()
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        let textStorage = NSTextStorage()

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = CustomTextView(frame: .zero, textContainer: textContainer)
        textView.isScrollEnabled = false  // Disable scrolling - text view grows to fit content
        textView.font = font
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.keyboardDismissMode = .none
        textView.showsVerticalScrollIndicator = false

        textView.textContainerInset = UIEdgeInsets(
            top: padding.top,
            left: padding.leading,
            bottom: padding.bottom,
            right: padding.trailing
        )

        // Set up keyboard observer
        context.coordinator.textView = textView
        context.coordinator.setupKeyboardObserver()

        return textView
    }

    func updateUIView(_ uiView: CustomTextView, context: Context) {
        // Update text if changed
        if uiView.text != text {
            uiView.text = text
        }

        // Handle first responder
        if shouldBecomeFirstResponder && !context.coordinator.hasBecomefirstResponder {
            context.coordinator.hasBecomefirstResponder = true
            context.coordinator.shouldScrollToCursor = true
            print("Setting shouldScrollToCursor = true, will scroll after keyboard shows")

            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
                // Move cursor to end of text
                let endPosition = uiView.endOfDocument
                uiView.selectedTextRange = uiView.textRange(from: endPosition, to: endPosition)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: UITextViewWrapper
        var hasBecomefirstResponder = false
        var shouldScrollToCursor = false
        weak var textView: UITextView?

        init(_ parent: UITextViewWrapper) {
            self.parent = parent
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func setupKeyboardObserver() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidShow),
                name: UIResponder.keyboardDidShowNotification,
                object: nil
            )
        }

        @objc func keyboardDidShow() {
            // Text view is non-scrollable and sizes to content
            // The outer ScrollView handles scrolling
            // Nothing to do here - just clear the flag
            shouldScrollToCursor = false
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
