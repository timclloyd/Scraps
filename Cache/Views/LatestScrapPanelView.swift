//
//  LatestScrapPanelView.swift
//  Cache
//

import SwiftUI
import SmoothGradient

struct LatestScrapPanelView: View {
    @EnvironmentObject var documentManager: DocumentManager
    let keyboardHeight: CGFloat
    let viewMode: ViewMode
    let editorFont: UIFont

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Preferences.latestPanelCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Preferences.latestPanelCornerRadius
        )

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let latestScrap = documentManager.scraps.last {
                        ScrapCardView(
                            scrap: latestScrap,
                            showsSeparator: false,
                            autoFocus: latestScrap.id == documentManager.focusedScrapID && viewMode == .latest,
                            topPadding: 18,
                            editorFont: editorFont
                        )
                    }
                }
                .padding(.bottom, Theme.textSize)
            }
            .scrollDismissesKeyboard(.never)
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, keyboardHeight, for: .scrollContent)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            .background(Theme.latestPanelBackground)
            .overlay(alignment: .top) {
                SmoothLinearGradient(
                    from: Theme.latestPanelBackground.opacity(0.9),
                    to: Theme.latestPanelBackground.opacity(0),
                    startPoint: .top, endPoint: .bottom, curve: .easeOut
                )
                .frame(height: Theme.topFadeHeight)
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            shape.strokeBorder(Color(Theme.panelBorderColor), lineWidth: 1)
        }
    }
}
