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
    var horizontalPadding: CGFloat = 2
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
            .alert("Delete All Text?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    currentText = ""
                    document.lines.removeAll()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
}

struct TextEditorView: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont
    var padding: EdgeInsets
    var onShake: () -> Void

    func makeUIView(context: Context) -> ShakeableTextView { // Change return type
        let textView = ShakeableTextView()
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
        textView.showsVerticalScrollIndicator = false
        textView.onShake = onShake // Set the callback
        return textView
    }
    
    func updateUIView(_ uiView: ShakeableTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
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
    
    // Make sure shake detection is enabled
    override var canBecomeFirstResponder: Bool {
        return true
    }
}
