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
    final class Coordinator: NSObject {
        var parent: ScrapPreviewView
        weak var textView: PreviewTextView?
        var lastActiveSearchRange: NSRange?

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
}
