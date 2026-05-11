//
//  ScrapPreviewView.swift
//  Cache
//
//  Read-only preview of a scrap for use in the archive list.
//
//  A full `TextEditorView` (UITextView + NSLayoutManager + regex compilation +
//  autocorrect + gesture recognisers) per archive card is expensive to instantiate
//  and lay out — this caused visible scroll hitches on long scraps. This view
//  replaces the editor for non-focused cards with a cheap read-only UITextView
//  that reuses the same `TextHighlightManager`, text-container insets, and font.
//
//  Why UITextView rather than SwiftUI `Text`: SwiftUI `Text` and UITextView use
//  different layout engines (Core Text vs TextKit 1), so a glyph that wraps at
//  column N in one can fit at column N in the other. That caused a visible line
//  re-wrap every time a card gained or lost focus. Sharing the TextKit stack
//  guarantees pixel-identical wrapping with the editing view.
//
//  Tap handling: plain taps promote the card to the full editor and carry the
//  tap location through `DocumentManager.pendingFocusTapLocation` so the editor's
//  caret lands where the user tapped. Taps that land on a `.link` attribute open
//  the URL directly without promoting.

import SwiftUI
import AudioToolbox

private enum ScrapPreviewFeedback {
    static let strikethroughSoundID: SystemSoundID = 1306
}

struct ScrapPreviewView: UIViewRepresentable {
    let scrap: Scrap
    @ObservedObject var document: TextDocument
    let font: UIFont
    var searchQuery: String = ""
    var activeSearchRange: NSRange? = nil

    @EnvironmentObject var documentManager: DocumentManager

    func makeUIView(context: Context) -> PreviewTextView {
        let layoutManager = TextHighlightManager()
        layoutManager.normalFont = font
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = PreviewTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: Theme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = true
        textView.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleStrikethroughPan(_:)))
        pan.delegate = context.coordinator
        textView.addGestureRecognizer(pan)

        context.coordinator.textView = textView

        textView.text = document.text
        if let lm = textView.textStorage.layoutManagers.first as? TextHighlightManager {
            lm.searchQuery = searchQuery
            lm.activeSearchRange = activeSearchRange
            lm.highlightKeywords = documentManager.highlightSettings.keywords
        }

        return textView
    }

    func updateUIView(_ uiView: PreviewTextView, context: Context) {
        context.coordinator.parent = self

        if uiView.text != document.text {
            uiView.text = document.text
        }
        if let lm = uiView.textStorage.layoutManagers.first as? TextHighlightManager {
            lm.normalFont = font
            lm.searchQuery = searchQuery
            lm.activeSearchRange = activeSearchRange
            lm.highlightKeywords = documentManager.highlightSettings.keywords
        }
        if uiView.font != font {
            uiView.font = font
        }

        if activeSearchRange != context.coordinator.lastActiveSearchRange {
            context.coordinator.lastActiveSearchRange = activeSearchRange
            if let range = activeSearchRange {
                DispatchQueue.main.async {
                    context.coordinator.scrollToRange(range, in: uiView)
                }
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PreviewTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ScrapPreviewView
        weak var textView: PreviewTextView?
        var lastActiveSearchRange: NSRange?
        private var gestureLineRange: NSRange?
        private var gestureLineIsStruck = false

        init(_ parent: ScrapPreviewView) { self.parent = parent }

        func scrollToRange(_ range: NSRange, in textView: UITextView, retrying: Bool = false) {
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { return }
            var rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            rect = rect.insetBy(dx: -8, dy: 0)
            rect.origin.y -= Theme.topFadeHeight
            rect.size.height += Theme.topFadeHeight + Theme.cursorScrollPadding
            guard let scrollView = findParentScrollView(from: textView) else {
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
            var current: UIView? = view.superview
            while let v = current {
                if let sv = v as? UIScrollView { return sv }
                current = v.superview
            }
            return nil
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView = textView else { return }
            let point = recognizer.location(in: textView)

            if let url = url(at: point, in: textView) {
                UIApplication.shared.open(url)
                return
            }

            parent.documentManager.setFocusedScrap(
                id: parent.scrap.id,
                filename: parent.scrap.filename,
                tapLocation: point
            )
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: textView)
            return abs(velocity.x) > abs(velocity.y) * 2
        }

        @objc func handleStrikethroughPan(_ pan: UIPanGestureRecognizer) {
            guard let textView else { return }
            let translation = pan.translation(in: textView)
            let isRightSwipe = translation.x > 0

            switch pan.state {
            case .began:
                let location = pan.location(in: textView)
                guard let textPosition = textView.closestPosition(to: location) else { return }
                let charIndex = textView.offset(from: textView.beginningOfDocument, to: textPosition)
                let lineRange = (textView.text as NSString).paragraphRange(for: NSRange(location: charIndex, length: 0))
                let lineText = (textView.text as NSString).substring(with: lineRange)
                let content = lineText.hasSuffix("\n") ? String(lineText.dropLast()) : lineText
                guard !content.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                gestureLineRange = lineRange
                gestureLineIsStruck = StrikethroughLineMutation.isStruck(content)

            case .ended:
                defer { gestureLineRange = nil }
                guard let lineRange = gestureLineRange, abs(translation.x) > 60 else { return }
                let actionable = isRightSwipe ? !gestureLineIsStruck : gestureLineIsStruck
                guard actionable else { return }

                let currentText = parent.document.text
                guard lineRange.upperBound <= (currentText as NSString).length else { return }
                let lineText = (currentText as NSString).substring(with: lineRange)
                guard let mutation = StrikethroughLineMutation.result(for: lineText, isRightSwipe: isRightSwipe) else { return }

                let updatedText = (currentText as NSString).replacingCharacters(in: lineRange, with: mutation.replacement)
                parent.documentManager.textDidChange(for: parent.scrap, newText: updatedText)
                textView.text = updatedText

                UIImpactFeedbackGenerator(style: Theme.strikethroughHapticStyle).impactOccurred()
                AudioServicesPlaySystemSound(ScrapPreviewFeedback.strikethroughSoundID)

            case .cancelled, .failed:
                gestureLineRange = nil

            default:
                break
            }
        }

        // Link hit-testing: map the tap point to a character index and check for
        // a `.link` attribute. Uses the layout manager's glyph-fraction so taps
        // past the end of a line don't spuriously hit the first character of the
        // next line.
        private func url(at point: CGPoint, in textView: UITextView) -> URL? {
            guard textView.textStorage.length > 0 else { return nil }
            let layoutManager = textView.layoutManager
            let container = textView.textContainer
            var fraction: CGFloat = 0
            let glyphIndex = layoutManager.glyphIndex(for: point,
                                                     in: container,
                                                     fractionOfDistanceThroughGlyph: &fraction)
            guard glyphIndex < layoutManager.numberOfGlyphs, fraction < 1.0 else { return nil }
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            guard charIndex < textView.textStorage.length else { return nil }
            let value = textView.textStorage.attribute(.link, at: charIndex, effectiveRange: nil)
            if let url = value as? URL { return url }
            if let string = value as? String { return URL(string: string) }
            return nil
        }
    }
}

// Subclass exists so UIViewRepresentable's generic argument is concrete and so we
// can opt out of UITextView's default first-responder behaviour — the preview
// should never steal focus or show a caret.
final class PreviewTextView: UITextView {
    override var canBecomeFirstResponder: Bool { false }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(postToggleSearchCommand)),
            UIKeyCommand(input: ",", modifierFlags: .command, action: #selector(postTogglePreferencesCommand)),
            UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(postOpenRandomArchiveScrapCommand)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(postDismissPresentedUICommand)),
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .command, action: #selector(postPreviousSearchMatchCommand)),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: .command, action: #selector(postNextSearchMatchCommand)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: .command, action: #selector(postScrollArchiveToTopCommand)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: .command, action: #selector(postScrollArchiveToBottomCommand))
        ]
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

    @objc private func postScrollArchiveToTopCommand() {
        NotificationCenter.default.post(name: .scrapsScrollArchiveToTop, object: nil)
    }

    @objc private func postScrollArchiveToBottomCommand() {
        NotificationCenter.default.post(name: .scrapsScrollArchiveToBottom, object: nil)
    }
}
