//
//  TextEditorView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//
//  SwiftUI text editor component with syntax highlighting and custom behaviors.
//
//  Architecture:
//  - TextEditorView: Public SwiftUI component (UIViewRepresentable wrapper)
//  - EnhancedTextView: Private UITextView subclass with app-specific enhancements
//    (shake gesture, tap-to-focus, custom styling, keyboard behavior)

import SwiftUI

// MARK: - TextEditorView (Public SwiftUI Component)

struct TextEditorView: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EnhancedTextView, context: Context) -> CGSize? {
        // Tell SwiftUI to use the proposed width but let height grow based on content
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeUIView(context: Context) -> EnhancedTextView {
        let layoutManager = TextHighlightManager()
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        let textStorage = NSTextStorage()

        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = EnhancedTextView(frame: .zero, textContainer: textContainer)
        textView.isScrollEnabled = false  // Disable scrolling - text view grows to fit content
        textView.font = font
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.showsVerticalScrollIndicator = false

        // Remove default text container insets so text aligns with separator
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0

        // Auto-focus new text views (for newly created scraps)
        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }

        return textView
    }

    func updateUIView(_ uiView: EnhancedTextView, context: Context) {
        // Update text if changed
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

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Auto-scroll to keep cursor visible during keyboard navigation
            // Without this, arrow keys move cursor but view doesn't scroll (poor UX on macOS)
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }
}

// MARK: - EnhancedTextView (Private UIKit Implementation)

class EnhancedTextView: UITextView {
    var onShake: (() -> Void)?

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupTextView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextView()
    }

    private func setupTextView() {
        isSelectable = true
        isEditable = true

        // Subtle link styling to match minimal aesthetic (gray + underline)
        linkTextAttributes = [
            .foregroundColor: Theme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        // Custom cursor color to match accent color scheme
        tintColor = Theme.dynamicCursorColor(for: UITraitCollection.current)

        // Disable spell check to avoid red underlines (visual clutter)
        // but keep autocorrect suggestions for better typing experience
        spellCheckingType = .no
        autocorrectionType = .yes
    }

    // Detects device shake gesture to trigger clear action
    // Warning haptic provides physical feedback that gesture was registered
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            onShake?()
        }
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    // Ensures keyboard appears on first tap without requiring double-tap
    // Improves UX for quick text entry
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }

    // Clear inputView before resigning to prevent custom input views
    // from persisting and interfering with keyboard restoration
    override func resignFirstResponder() -> Bool {
        self.inputView = nil
        return super.resignFirstResponder()
    }
}
