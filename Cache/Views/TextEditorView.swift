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
    var scrapID: String?
    var onBecomeFocused: ((String) -> Void)?

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: EnhancedTextView, context: Context) -> CGSize? {
        // Tell SwiftUI to use the proposed width but let height grow based on content
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeUIView(context: Context) -> EnhancedTextView {
        let layoutManager = TextHighlightManager()
        layoutManager.normalFont = font
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
        context.coordinator.parent = self

        if let lm = uiView.textStorage.layoutManagers.first as? TextHighlightManager {
            lm.normalFont = font
        }

        // Update text if changed
        if uiView.text != text {
            uiView.text = text
        }

        // Reset so next isInitialFocus = true transition triggers becomeFirstResponder again
        if !isInitialFocus {
            context.coordinator.hasFocused = false
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
        private var keyboardDidShowObserver: NSObjectProtocol?

        init(_ parent: TextEditorView) {
            self.parent = parent
            super.init()

            // Listen for keyboard appearing to adjust scroll position
            keyboardDidShowObserver = NotificationCenter.default.addObserver(
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

        deinit {
            if let keyboardDidShowObserver {
                NotificationCenter.default.removeObserver(keyboardDidShowObserver)
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

class EnhancedTextView: UITextView, UIGestureRecognizerDelegate {
    var onBecomeFocused: (() -> Void)?

    private let strikethroughPreviewLayer = CAShapeLayer()
    private var gestureLineRange: NSRange?
    private var gestureLineIsStruck = false

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

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleStrikethroughPan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

        strikethroughPreviewLayer.lineWidth = 1.5
        strikethroughPreviewLayer.lineCap = .round
        strikethroughPreviewLayer.opacity = 0
        layer.addSublayer(strikethroughPreviewLayer)
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

    // MARK: - UIGestureRecognizerDelegate

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer, pan.delegate === self else { return true }
        let v = pan.velocity(in: self)
        return abs(v.x) > abs(v.y) * 2
    }

    // MARK: - Strikethrough Gesture

    @objc private func handleStrikethroughPan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self)
        let isRightSwipe = translation.x > 0

        switch pan.state {
        case .began:
            let location = pan.location(in: self)
            guard let textPos = closestPosition(to: location) else { return }
            let charIndex = offset(from: beginningOfDocument, to: textPos)
            let nsRange = (text as NSString).paragraphRange(for: NSRange(location: charIndex, length: 0))
            let lineText = (text as NSString).substring(with: nsRange)
            let content = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
            guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            gestureLineRange = nsRange
            gestureLineIsStruck = content.hasPrefix("~~") && content.hasSuffix("~~") && content.count > 4

        case .changed:
            guard let lineRange = gestureLineRange else { return }
            guard isRightSwipe && !gestureLineIsStruck else { clearStrikethroughPreview(); return }
            updateStrikethroughPreview(for: lineRange, progress: abs(translation.x))

        case .ended:
            clearStrikethroughPreview()
            guard let lineRange = gestureLineRange, abs(translation.x) > 60 else {
                gestureLineRange = nil
                return
            }
            let actionable = isRightSwipe ? !gestureLineIsStruck : gestureLineIsStruck
            guard actionable else { gestureLineRange = nil; return }

            let lineText = (text as NSString).substring(with: lineRange)
            let content = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
            let suffix = lineText.hasSuffix("\n") ? "\n" : ""
            let newContent: String
            if isRightSwipe {
                newContent = "~~\(content)~~"
            } else {
                let canRemove = content.hasPrefix("~~") && content.hasSuffix("~~") && content.count > 4
                newContent = canRemove ? String(content.dropFirst(2).dropLast(2)) : content
            }
            let savedLocation = selectedRange.location
            let newRange = NSRange(location: lineRange.location, length: (newContent + suffix).utf16.count)

            textStorage.beginEditing()
            textStorage.replaceCharacters(in: lineRange, with: newContent + suffix)
            // New chars inherit attributes from the first replaced character (gray foreground,
            // strikethrough). Restore normal attributes so processEditing sees a clean slate.
            if let font = self.font {
                textStorage.addAttribute(.font, value: font, range: newRange)
            }
            if let color = self.textColor {
                textStorage.addAttribute(.foregroundColor, value: color, range: newRange)
            }
            textStorage.endEditing()

            delegate?.textViewDidChange?(self)

            // Adjust cursor for the ~~ chars added/removed at both ends of the line.
            // Positions before the trailing marker only need +/-2 (leading pair);
            // positions at or after the trailing marker need +/-4 (both pairs).
            let adjustedLocation: Int
            if savedLocation >= lineRange.location && savedLocation <= lineRange.upperBound {
                if isRightSwipe {
                    let trailingInsertPos = lineRange.location + content.utf16.count
                    adjustedLocation = savedLocation >= trailingInsertPos ? savedLocation + 4 : savedLocation + 2
                } else {
                    let trailingMarkerStart = lineRange.location + content.utf16.count - 2
                    if savedLocation >= trailingMarkerStart {
                        adjustedLocation = lineRange.location + content.utf16.count - 4
                    } else {
                        adjustedLocation = max(lineRange.location, savedLocation - 2)
                    }
                }
            } else {
                adjustedLocation = savedLocation
            }
            selectedRange = NSRange(location: min(adjustedLocation, textStorage.length), length: 0)
            gestureLineRange = nil

        case .cancelled, .failed:
            clearStrikethroughPreview()
            gestureLineRange = nil

        default:
            break
        }
    }

    private func updateStrikethroughPreview(for lineRange: NSRange, progress: CGFloat) {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return }
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
        guard lineRect != .zero else { return }

        let strikeY = lineRect.midY + lineRect.height * 0.1
        let startX = lineRect.minX
        let endX = min(startX + progress, lineRect.maxX)

        let path = UIBezierPath()
        path.move(to: CGPoint(x: startX, y: strikeY))
        path.addLine(to: CGPoint(x: endX, y: strikeY))

        strikethroughPreviewLayer.strokeColor = UIColor.label.cgColor
        strikethroughPreviewLayer.path = path.cgPath
        strikethroughPreviewLayer.opacity = 1
    }

    private func clearStrikethroughPreview() {
        strikethroughPreviewLayer.opacity = 0
        strikethroughPreviewLayer.path = nil
    }
}
