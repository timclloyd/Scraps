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
    
    var textSize: CGFloat = 16
    var horizontalPadding: CGFloat = 16
    var verticalPadding: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            TextEditorView(
                text: $currentText,
                font: UIFont(name: "JetBrainsMono-Regular", size: textSize) ?? UIFont.systemFont(ofSize: textSize),
                padding: EdgeInsets(
                    top: verticalPadding,
                    leading: horizontalPadding,
                    bottom: verticalPadding,
                    trailing: horizontalPadding
                )
            )
            .focused($isFocused)
            .onAppear {
                isFocused = true // Focus cursor at the end when the view appears
            }
            .onChange(of: currentText) { newValue in
                // Auto-save when the text changes
                if !newValue.isEmpty {
                    document.addLine(newValue)
                }
            }
        }
    }
}

struct TextEditorView: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont
    var padding: EdgeInsets
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isScrollEnabled = true
        textView.font = font
        textView.delegate = context.coordinator
        textView.text = text
        textView.backgroundColor = .clear
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(
            top: padding.top,
            left: padding.leading,
            bottom: padding.bottom,
            right: padding.trailing
        )
        
        DispatchQueue.main.async {
            let endPosition = textView.endOfDocument
            textView.scrollRangeToVisible(NSRange(location: textView.offset(from: textView.beginningOfDocument, to: endPosition), length: 0))
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        let endPosition = uiView.endOfDocument
        uiView.scrollRangeToVisible(NSRange(location: uiView.offset(from: uiView.beginningOfDocument, to: endPosition), length: 0))
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
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            let endPosition = textView.endOfDocument
            textView.selectedTextRange = textView.textRange(from: endPosition, to: endPosition)
        }
    }
}
