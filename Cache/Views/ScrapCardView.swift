//
//  ScrapCardView.swift
//  Cache
//

import SwiftUI

struct ScrapCardView: View {
    @EnvironmentObject var documentManager: DocumentManager
    let scrap: Scrap
    let showsSeparator: Bool
    let autoFocus: Bool
    var focusRequestID: Int = 0
    var topPadding: CGFloat = Theme.textSize
    var cardBackground: Color = .clear
    let editorFont: UIFont
    var searchQuery: String = ""
    var activeSearchRange: NSRange? = nil
    // When true, the card always uses the full editor (e.g. for the latest-scrap
    // panel, which is singular and inexpensive). Archive list callers leave this
    // false so non-focused cards render via the cheap read-only preview.
    var forceEditor: Bool = false

    private var isFocused: Bool {
        documentManager.focusedScrapID == scrap.id
    }

    // Keeps the editor mounted briefly after focus moves elsewhere so UIKit can
    // hand first responder to the next card's editor without the keyboard ever
    // seeing "no first responder" and dismissing. Without this, SwiftUI unmounts
    // the old `UITextView` a frame or two before the new one mounts.
    @State private var retainEditor: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if showsSeparator {
                SeparatorView(timestamp: scrap.timestamp)
                    .padding(.vertical, Theme.separatorVerticalPadding / 2 - Theme.horizontalPaddingBackground)
                    .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
            }

            Group {
                if forceEditor || isFocused || autoFocus || retainEditor {
                    // For cards that share a single always-mounted editor (the latest panel,
                    // `forceEditor: true`), `isFocused` is sticky across archive trips and
                    // would mask the archive→latest transition, so we rely on `autoFocus`
                    // alone to retrigger `becomeFirstResponder` after keyboard dismissal.
                    // Archive cards mount their editor fresh on focus, so `isFocused` is
                    // the right trigger there.
                    ScrapView(
                        scrap: scrap,
                        document: scrap.document,
                        font: editorFont,
                        isInitialFocus: forceEditor ? autoFocus : (autoFocus || isFocused),
                        focusRequestID: focusRequestID,
                        searchQuery: searchQuery,
                        activeSearchRange: activeSearchRange
                    )
                } else {
                    ScrapPreviewView(
                        scrap: scrap,
                        document: scrap.document,
                        font: editorFont,
                        searchQuery: searchQuery,
                        activeSearchRange: activeSearchRange
                    )
                }
            }
            .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
            .padding(.bottom, Theme.separatorVerticalPadding - Theme.horizontalPaddingBackground)
        }
        .background(cardBackground)
        .cornerRadius(12)
        .padding(.horizontal, Theme.horizontalPaddingBackground)
        .id(scrap.id)
        .padding(.top, topPadding)
        .onChange(of: isFocused) { _, nowFocused in
            if nowFocused {
                retainEditor = true
            } else {
                // Window long enough for the next card's editor to mount and take
                // first responder, short enough that a lingering editor is never
                // visible to the user (preview is pixel-equivalent at rest anyway).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !isFocused { retainEditor = false }
                }
            }
        }
    }
}
