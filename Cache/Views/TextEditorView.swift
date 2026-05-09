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
import AudioToolbox

private enum TextEditorFeedback {
    static let strikethroughSoundID: SystemSoundID = 1306
}

// MARK: - TextEditorView (Public SwiftUI Component)

struct TextEditorView: UIViewRepresentable {
    @EnvironmentObject var documentManager: DocumentManager

    @Binding var text: String
    var font: UIFont
    var isInitialFocus: Bool = false
    var focusRequestID: Int = 0
    var scrapID: String?
    var onBecomeFocused: ((String) -> Void)?
    var searchQuery: String = ""
    var activeSearchRange: NSRange? = nil
    // Optional tap point (in the text view's local coordinate space) captured from
    // the archive preview. When present, the caret is placed at the closest
    // character position on first-responder acquisition instead of defaulting to
    // the end of the text. Cleared after use by the caller.
    var initialTapLocation: CGPoint? = nil

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
        textView.onAttachedToWindow = { [weak coordinator = context.coordinator] in
            coordinator?.attemptPendingInitialFocus()
        }

        // Store reference in coordinator for keyboard notification
        context.coordinator.textView = textView

        return textView
    }

    func updateUIView(_ uiView: EnhancedTextView, context: Context) {
        context.coordinator.parent = self

        if let lm = uiView.textStorage.layoutManagers.first as? TextHighlightManager {
            lm.normalFont = font
            lm.searchQuery = searchQuery
            lm.activeSearchRange = activeSearchRange
            lm.highlightKeywords = documentManager.highlightSettings.keywords
        }

        // Update text if changed
        if uiView.text != text {
            uiView.text = text
        }

        // Scroll to active search match when it changes
        if activeSearchRange != context.coordinator.lastActiveSearchRange {
            context.coordinator.lastActiveSearchRange = activeSearchRange
            if let range = activeSearchRange {
                DispatchQueue.main.async {
                    context.coordinator.scrollToRange(range, in: uiView)
                }
            }
        }

        // Reset so next isInitialFocus = true transition triggers becomeFirstResponder again
        if !isInitialFocus {
            context.coordinator.hasFocused = false
            context.coordinator.cancelPendingInitialFocus()
        }

        // `focusedScrapID` is selection state. `focusRequestID` is the separate
        // command to make this UIKit editor first responder, consumed once when
        // the view is in a window.
        if isInitialFocus && focusRequestID != context.coordinator.lastHandledFocusRequestID {
            context.coordinator.requestInitialFocus(
                focusRequestID,
                for: uiView,
                tapLocation: initialTapLocation
            )
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: TextEditorView
        var hasFocused = false
        weak var textView: UITextView?
        var lastActiveSearchRange: NSRange?
        var keyboardHeight: CGFloat = 0
        var lastHandledFocusRequestID = 0
        private var keyboardObservers: [NSObjectProtocol] = []
        private weak var pendingFocusTextView: EnhancedTextView?
        private var pendingFocusRequestID: Int?
        private var pendingFocusTapLocation: CGPoint?

        init(_ parent: TextEditorView) {
            self.parent = parent
            super.init()

            let show = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    self?.keyboardHeight = frame.height
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard let self = self, let textView = self.textView, textView.isFirstResponder else { return }
                    self.scrollToKeepCursorVisible(in: textView)
                }
            }

            let hide = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.keyboardHeight = 0
            }

            keyboardObservers = [show, hide]
        }

        deinit {
            keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func cancelPendingInitialFocus() {
            pendingFocusTextView = nil
            pendingFocusRequestID = nil
            pendingFocusTapLocation = nil
        }

        func requestInitialFocus(
            _ requestID: Int,
            for textView: EnhancedTextView,
            tapLocation: CGPoint?
        ) {
            pendingFocusTextView = textView
            pendingFocusRequestID = requestID
            pendingFocusTapLocation = tapLocation
            attemptPendingInitialFocus()
        }

        func attemptPendingInitialFocus() {
            guard parent.isInitialFocus,
                  let requestID = pendingFocusRequestID,
                  requestID != lastHandledFocusRequestID,
                  let textView = pendingFocusTextView,
                  textView.window != nil else { return }

            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self,
                      self.parent.isInitialFocus,
                      let requestID = self.pendingFocusRequestID,
                      requestID != self.lastHandledFocusRequestID,
                      let textView,
                      textView.window != nil else { return }

                let didFocus = textView.becomeFirstResponder()
                self.hasFocused = didFocus
                guard didFocus else { return }

                self.lastHandledFocusRequestID = requestID
                if let point = self.pendingFocusTapLocation,
                   let position = textView.closestPosition(to: point) {
                    textView.selectedTextRange = textView.textRange(from: position, to: position)
                }
                self.cancelPendingInitialFocus()
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

            let cursorRect = textView.caretRect(for: selectedRange.start)

            guard let scrollView = findParentScrollView(from: textView) else {
                textView.scrollRangeToVisible(textView.selectedRange)
                return
            }

            let cursorInScroll = textView.convert(cursorRect, to: scrollView)
            let visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset)

            // Skip when the caret itself is already within the visible area — the
            // padded rect used below always extends beyond the cursor, so without
            // this check every line-wrap nudges the scroll view by a few points.
            if visible.contains(CGPoint(x: cursorInScroll.midX, y: cursorInScroll.minY))
                && visible.contains(CGPoint(x: cursorInScroll.midX, y: cursorInScroll.maxY)) {
                return
            }

            var paddedRect = cursorRect
            paddedRect.origin.y -= Theme.cursorScrollPadding
            paddedRect.size.height += Theme.cursorScrollPadding * 2
            let paddedInScroll = textView.convert(paddedRect, to: scrollView)
            scrollView.scrollRectToVisible(paddedInScroll, animated: true)
        }

        func scrollToRange(_ range: NSRange, in textView: UITextView, retrying: Bool = false) {
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { return }
            var rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            rect = rect.insetBy(dx: -8, dy: 0)
            rect.origin.y -= Theme.topFadeHeight
            rect.size.height += Theme.topFadeHeight + Theme.cursorScrollPadding + keyboardHeight
            guard let scrollView = findParentScrollView(from: textView) else {
                // View not yet in hierarchy (lazy rendering) — retry once after materialisation
                guard !retrying else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak textView] in
                    guard let textView else { return }
                    self?.scrollToRange(range, in: textView, retrying: true)
                }
                return
            }
            let rectInScrollView = textView.convert(rect, to: scrollView)
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
    var onAttachedToWindow: (() -> Void)?

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

        tintColor = Theme.textInputTintColor

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

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(postToggleSearchCommand)),
            UIKeyCommand(input: ",", modifierFlags: .command, action: #selector(postTogglePreferencesCommand)),
            UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(postOpenRandomArchiveScrapCommand)),
            UIKeyCommand(input: "d", modifierFlags: .command, action: #selector(toggleStrikethroughFocusedLineCommand)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(postDismissPresentedUICommand)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .command, action: #selector(postPreviousSearchMatchCommand)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: .command, action: #selector(postNextSearchMatchCommand))
        ]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            onAttachedToWindow?()
        }
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

    @objc private func postToggleSearchCommand() {
        NotificationCenter.default.post(name: .scrapsToggleSearch, object: nil)
    }

    @objc private func postTogglePreferencesCommand() {
        NotificationCenter.default.post(name: .scrapsShowPreferences, object: nil)
    }

    @objc private func postDismissPresentedUICommand() {
        NotificationCenter.default.post(name: .scrapsDismissPresentedUI, object: nil)
    }

    @objc private func postOpenRandomArchiveScrapCommand() {
        NotificationCenter.default.post(name: .scrapsOpenRandomArchiveScrap, object: nil)
    }

    @objc private func postPreviousSearchMatchCommand() {
        NotificationCenter.default.post(name: .scrapsPreviousSearchMatch, object: nil)
    }

    @objc private func postNextSearchMatchCommand() {
        NotificationCenter.default.post(name: .scrapsNextSearchMatch, object: nil)
    }

    @objc private func toggleStrikethroughFocusedLineCommand() {
        let caretLocation = min(selectedRange.location, (text as NSString).length)
        let lineRange = (text as NSString).paragraphRange(for: NSRange(location: caretLocation, length: 0))
        toggleStrikethroughLine(in: lineRange)
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
            gestureLineIsStruck = StrikethroughLineMutation.isStruck(content)

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
            guard let mutation = StrikethroughLineMutation.result(for: lineText, isRightSwipe: isRightSwipe) else {
                gestureLineRange = nil
                return
            }
            applyStrikethroughMutation(mutation, to: lineRange)

            gestureLineRange = nil

        case .cancelled, .failed:
            clearStrikethroughPreview()
            gestureLineRange = nil

        default:
            break
        }
    }

    private func toggleStrikethroughLine(in lineRange: NSRange) {
        guard lineRange.upperBound <= (text as NSString).length else { return }
        let lineText = (text as NSString).substring(with: lineRange)
        let content = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
        let isRightSwipe = !StrikethroughLineMutation.isStruck(content)
        guard let mutation = StrikethroughLineMutation.result(for: lineText, isRightSwipe: isRightSwipe) else { return }
        applyStrikethroughMutation(mutation, to: lineRange)
    }

    private func applyStrikethroughMutation(_ mutation: StrikethroughLineMutation.Result, to lineRange: NSRange) {
        let newRange = NSRange(location: lineRange.location, length: mutation.replacement.utf16.count)

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: lineRange, with: mutation.replacement)
        // New chars inherit attributes from the first replaced character. Restore
        // normal attributes so processEditing sees a clean slate.
        if let font = self.font {
            textStorage.addAttribute(.font, value: font, range: newRange)
        }
        if let color = self.textColor {
            textStorage.addAttribute(.foregroundColor, value: color, range: newRange)
        }
        textStorage.endEditing()

        selectedRange = NSRange(location: lineRange.location + mutation.caretOffset, length: 0)

        UIImpactFeedbackGenerator(style: Theme.strikethroughHapticStyle).impactOccurred()
        AudioServicesPlaySystemSound(TextEditorFeedback.strikethroughSoundID)

        delegate?.textViewDidChange?(self)
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
