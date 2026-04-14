//
//  ScrapCardView.swift
//  Cache
//

import SwiftUI

struct ScrapCardView: View {
    let scrap: Scrap
    let showsSeparator: Bool
    let autoFocus: Bool
    var topPadding: CGFloat = Theme.textSize
    let editorFont: UIFont

    var body: some View {
        VStack(spacing: 0) {
            if showsSeparator {
                SeparatorView(timestamp: scrap.timestamp)
                    .padding(.vertical, Theme.separatorVerticalPadding / 2 - Theme.horizontalPaddingBackground)
                    .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
            }

            ScrapView(
                scrap: scrap,
                document: scrap.document,
                font: editorFont,
                isInitialFocus: autoFocus
            )
            .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
            .padding(.bottom, Theme.separatorVerticalPadding - Theme.horizontalPaddingBackground)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .padding(.horizontal, Theme.horizontalPaddingBackground)
        .id(scrap.id)
        .padding(.top, topPadding)
    }
}
