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
    var isInitialFocus: Bool = false
    var scrapID: UUID?
    var onBecomeFocused: ((UUID) -> Void)?

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

        // Set callback for when this view becomes focused
        let scrapID = scrapID
        let onBecomeFocused = onBecomeFocused
        textView.onBecomeFocused = {
            if let scrapID = scrapID {
                onBecomeFocused?(scrapID)
            }
        }

        // Store reference in coordinator for keyboard notification
        context.coordinator.textView = textView

        return textView
    }

    func updateUIView(_ uiView: EnhancedTextView, context: Context) {
        // Update text if changed
        if uiView.text != text {
            uiView.text = text
        }

        // Auto-focus only if this is marked for initial focus and hasn't focused yet
        // No delay needed - proper sequencing ensures scroll completes before focus
        if isInitialFocus && !context.coordinator.hasFocused && !uiView.isFirstResponder {
            context.coordinator.hasFocused = true
            // Double-check view is still in hierarchy before focusing
            if uiView.superview != nil {
                uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextEditorView
        var hasFocused = false
        weak var textView: UITextView?

        init(_ parent: TextEditorView) {
            self.parent = parent
            super.init()

            // Listen for keyboard appearing to adjust scroll position
            NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // After keyboard appears, adjust scroll to add padding
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard let self = self, let textView = self.textView, textView.isFirstResponder else { return }
                    self.scrollToKeepCursorVisible(in: textView)
                }
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            // Also keep cursor visible when text changes (e.g., typing newlines)
            // Force layout update, then scroll after a tiny delay to override iOS's automatic scroll
            textView.layoutIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.scrollToKeepCursorVisible(in: textView)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Keep cursor visible with comfortable padding above keyboard
            scrollToKeepCursorVisible(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Called when text view becomes first responder
            if let scrapID = parent.scrapID {
                parent.onBecomeFocused?(scrapID)
            }
        }

        private func scrollToKeepCursorVisible(in textView: UITextView) {
            guard let selectedRange = textView.selectedTextRange else { return }

            // Get cursor position rect
            var cursorRect = textView.caretRect(for: selectedRange.start)

            // Add padding above and below the cursor
            cursorRect.origin.y -= Theme.cursorScrollPadding         // Move rect up to add padding above
            cursorRect.size.height += Theme.cursorScrollPadding * 2  // Extend height for padding both above and below

            // Find the parent UIScrollView
            guard let scrollView = findParentScrollView(from: textView) else {
                // Fallback to default behavior if we can't find scroll view
                textView.scrollRangeToVisible(textView.selectedRange)
                return
            }

            // Convert cursor rect to scroll view's coordinate space
            let rectInScrollView = textView.convert(cursorRect, to: scrollView)

            // Scroll to make the padded rect visible
            scrollView.scrollRectToVisible(rectInScrollView, animated: true)
        }

        private func findParentScrollView(from view: UIView) -> UIScrollView? {
            var currentView: UIView? = view.superview
            while let view = currentView {
                if let scrollView = view as? UIScrollView {
                    return scrollView
                }
                currentView = view.superview
            }
            return nil
        }
    }
}

// MARK: - EnhancedTextView (Private UIKit Implementation)

class EnhancedTextView: UITextView {
    var onShake: (() -> Void)?
    var onBecomeFocused: (() -> Void)?

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
        tintColor = Theme.cursorColor(for: UITraitCollection.current)

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
