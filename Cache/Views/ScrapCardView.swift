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

    var body: some View {
        VStack(spacing: 0) {
            if showsSeparator {
                SeparatorView(timestamp: scrap.timestamp)
                    .padding(.vertical, Theme.separatorVerticalPadding / 2 - Theme.horizontalPaddingBackground)
                    .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
            }

            Group {
                if forceEditor || isFocused || autoFocus {
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
    }
}
