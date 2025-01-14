//
//  UITextViewWrapper.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//
//  SwiftUI wrapper around a custom UITextView implementation
//  to workaround SwiftUI TextEditor not showing/hiding the keyboard
//  reliably and to make custom highlighting easier

import SwiftUI

struct  UITextViewWrapper: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont
    var padding: EdgeInsets
    var onShake: () -> Void

    func makeUIView(context: Context) -> CustomTextView {
        // Create text storage and layout manager
        let textStorage = NSTextStorage()
        let layoutManager = HighlightLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        // Create text container with proper size
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        
        // Create text view with our custom text system
        let textView = CustomTextView(frame: .zero, textContainer: textContainer)
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
    
    func updateUIView(_ uiView: CustomTextView, context: Context) {
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
        var parent:  UITextViewWrapper

        init(_ parent:  UITextViewWrapper) {
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
