//
//  ArchiveListView.swift
//  Cache
//

import SwiftUI
import SmoothGradient

struct ArchiveListView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @StateObject private var valenceIndex = ValenceIndex()
    let keyboardHeight: CGFloat
    let editorFont: UIFont
    var viewMode: ViewMode = .archive
    var searchQuery: String = ""
    var activeMatchScrapID: String? = nil
    var activeMatchRange: NSRange? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
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
                    .padding(.trailing, Theme.minimapWidth)
                }
                .background(Theme.archiveBackground)
                .scrollIndicators(.hidden)
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
                // Cross-scrap scroll: ScrollViewReader gets us to the target card
                // (and materialises it from the LazyVStack if off-screen). The
                // preview's own scrollRectToVisible then refines to the exact
                // match rect. Intra-scrap navigation relies solely on the latter.
                .onChange(of: activeMatchScrapID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }

                ArchiveMinimapView(
                    scraps: documentManager.scraps,
                    hits: valenceIndex.hits,
                    onTapScrap: { id in
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    },
                    onScrubScrap: { id in
                        proxy.scrollTo(id, anchor: .top)
                    }
                )
                .padding(.top, Theme.topFadeHeight)
                .padding(.bottom, Theme.bottomFadeHeight)
            }
            .onAppear {
                valenceIndex.bind(to: documentManager)
            }
        }
    }
}
