//
//  ArchiveListView.swift
//  Cache
//

import SwiftUI
import SmoothGradient

struct ArchiveListView: View {
    @EnvironmentObject var documentManager: DocumentManager
    let keyboardHeight: CGFloat
    let editorFont: UIFont
    var viewMode: ViewMode = .archive
    var searchQuery: String = ""
    var activeMatchScrapID: String? = nil
    var activeMatchRange: NSRange? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(documentManager.scraps.reversed())) { scrap in
                        ScrapCardView(
                            scrap: scrap,
                            showsSeparator: scrap.id != documentManager.scraps.last?.id,
                            autoFocus: false,
                            cardBackground: .clear,
                            editorFont: editorFont,
                            searchQuery: searchQuery,
                            activeSearchRange: scrap.id == activeMatchScrapID ? activeMatchRange : nil
                        )
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, Theme.textSize)
            }
            .background(Theme.archiveBackground)
            .scrollIndicators(.visible)
            .scrollDismissesKeyboard(.never)
            .contentMargins(.bottom, keyboardHeight, for: .scrollContent)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                SmoothLinearGradient(
                    from: Theme.archiveBackground,
                    to: Theme.archiveBackground.opacity(0),
                    startPoint: .top, endPoint: .bottom, curve: .easeOut
                )
                .frame(height: Theme.topFadeHeight)
                .allowsHitTesting(false)
            }
            .onChange(of: activeMatchScrapID) { _, id in
                guard let id else { return }
                withAnimation(.none) {
                    proxy.scrollTo(id)
                }
            }
        }
    }
}
