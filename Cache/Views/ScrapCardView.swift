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
                    ScrapView(
                        scrap: scrap,
                        document: scrap.document,
                        font: editorFont,
                        isInitialFocus: autoFocus || isFocused,
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
