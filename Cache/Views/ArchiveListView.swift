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
    var searchQuery: String = ""
    var activeMatchScrapID: String? = nil
    var activeMatchRange: NSRange? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(documentManager.scraps) { scrap in
                        ScrapCardView(
                            scrap: scrap,
                            showsSeparator: scrap.id != documentManager.scraps.first?.id,
                            autoFocus: false,
                            cardBackground: .clear,
                            editorFont: editorFont,
                            searchQuery: searchQuery,
                            activeSearchRange: scrap.id == activeMatchScrapID ? activeMatchRange : nil
                        )
                    }
                }
                .padding(.top, Theme.verticalPadding)
                .padding(.bottom, Theme.textSize)
                Color.clear.frame(height: 0).id("archiveListBottom")
            }
            .background(Theme.archiveBackground)
            .scrollDismissesKeyboard(.never)
            .contentMargins(.bottom, keyboardHeight, for: .scrollContent)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            .ignoresSafeArea(edges: .bottom)
            .defaultScrollAnchor(.bottom)
            .overlay(alignment: .top) {
                SmoothLinearGradient(
                    from: Theme.archiveBackground,
                    to: Theme.archiveBackground.opacity(0),
                    startPoint: .top, endPoint: .bottom, curve: .easeOut
                )
                .frame(height: Theme.topFadeHeight)
                .allowsHitTesting(false)
            }
            .onAppear {
                scrollToLatest(using: proxy)
            }
            .onChange(of: documentManager.scraps.count) { _, _ in
                scrollToLatest(using: proxy)
            }
            .onChange(of: activeMatchScrapID) { _, id in
                guard let id else { return }
                withAnimation(.none) {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo("archiveListBottom", anchor: .bottom)
        }
    }
}
