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
//  Why the UITextView is wrapped in a plain UIView with touches disabled on the
//  inner text view: even with `isSelectable=false` and `canBecomeFirstResponder=false`,
//  a tap landing on a UITextView triggers enough of its internal gesture stack
//  to resign the current first responder (the archive card the user is switching
//  away from), which drops the keyboard mid-animation on the first switch after
//  a cold launch. Making the UITextView non-interactive and mounting the tap
//  recogniser on the outer container keeps UITextView out of the touch path
//  entirely.
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

    func makeUIView(context: Context) -> PreviewContainerView {
        let layoutManager = TextHighlightManager()
        layoutManager.normalFont = font
        let textContainer = NSTextContainer(size: .zero)
        textContainer.widthTracksTextView = true
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = UITextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.backgroundColor = .clear
        textView.font = font
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: Theme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.translatesAutoresizingMaskIntoConstraints = false

        let container = PreviewContainerView(textView: textView)
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        container.addGestureRecognizer(tap)
        context.coordinator.container = container

        textView.text = document.text
        if let lm = textView.textStorage.layoutManagers.first as? TextHighlightManager {
            lm.searchQuery = searchQuery
            lm.activeSearchRange = activeSearchRange
        }

        return container
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        context.coordinator.parent = self

        let textView = uiView.textView
        if textView.text != document.text {
            textView.text = document.text
        }
        if let lm = textView.textStorage.layoutManagers.first as? TextHighlightManager {
            lm.normalFont = font
            lm.searchQuery = searchQuery
            lm.activeSearchRange = activeSearchRange
        }
        if textView.font != font {
            textView.font = font
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PreviewContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let size = uiView.textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScrapPreviewView
        weak var container: PreviewContainerView?

        init(_ parent: ScrapPreviewView) { self.parent = parent }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let container = container else { return }
            let point = recognizer.location(in: container.textView)

            if let url = url(at: point, in: container.textView) {
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

// Plain container so the outer tap recogniser owns the touch and UITextView's
// internal gesture stack never sees it. See file header for why that matters.
final class PreviewContainerView: UIView {
    let textView: UITextView

    init(textView: UITextView) {
        self.textView = textView
        super.init(frame: .zero)
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
