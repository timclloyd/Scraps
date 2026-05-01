//
//  ArchiveListView.swift
//  Cache
//

import SwiftUI
import SmoothGradient

private struct ScrapFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ArchiveListView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @StateObject private var valenceIndex = ValenceIndex()
    @StateObject private var archiveScrollViewStore = WeakScrollViewStore()
    @State private var visibleViewport: ArchiveMinimapViewport? = nil
    let keyboardHeight: CGFloat
    let editorFont: UIFont
    var viewMode: ViewMode = .archive
    var searchQuery: String = ""
    var activeMatchScrapID: String? = nil
    var activeMatchRange: NSRange? = nil
    @Binding var showsPreferences: Bool
    let toolbarHeight: CGFloat

    private static let archiveScrollCoordinateSpace = "ArchiveScrollCoordinateSpace"

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewportGeometry in
                HStack(spacing: 0) {
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
                                .background {
                                    GeometryReader { cardGeometry in
                                        Color.clear.preference(
                                            key: ScrapFramePreferenceKey.self,
                                            value: [scrap.id: cardGeometry.frame(in: .named(Self.archiveScrollCoordinateSpace))]
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.top, 2)
                        .padding(.bottom, Theme.textSize)
                    }
                    .coordinateSpace(name: Self.archiveScrollCoordinateSpace)
                    .background(Theme.archiveBackground)
                    .background(ScrollViewAccessor(store: archiveScrollViewStore))
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.never)
                    .contentMargins(.bottom, keyboardHeight + bottomToolbarHeight, for: .scrollContent)
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
                    .onPreferenceChange(ScrapFramePreferenceKey.self) { frames in
                        visibleViewport = makeVisibleViewport(
                            from: frames,
                            viewportHeight: max(viewportGeometry.size.height - bottomToolbarHeight, 0)
                        )
                    }

                    ArchiveMinimapView(
                        scraps: documentManager.scraps,
                        hits: valenceIndex.hits,
                        visibleViewport: visibleViewport,
                        onTapScrap: { id in
                            scrollToArchiveScrap(id, proxy: proxy, animated: true)
                        },
                        onScrubScrap: { id in
                            scrollToArchiveScrap(id, proxy: proxy, animated: false)
                        }
                    )
                    .padding(.top, Theme.textSize + 2)
                    .padding(.bottom, Theme.bottomFadeHeight + bottomToolbarHeight)
                    .background(Theme.archiveBackground)
                }
                .opacity(showsPreferences ? 0 : 1)
                .overlay(alignment: .bottom) {
                    if showsBottomToolbar {
                        bottomToolbar
                            .frame(height: toolbarHeight)
                            .background(Theme.archiveBackground)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .overlay {
                    if showsPreferences {
                        PreferencesView(searchButtonCenterTrailingInset: viewportGeometry.size.width / 6) {
                            withAnimation(Theme.navigationOut) {
                                showsPreferences = false
                            }
                        }
                        .environmentObject(documentManager)
                        .transition(.move(edge: .bottom))
                        .zIndex(1)
                        .ignoresSafeArea(edges: .bottom)
                    }
                }
                .onAppear {
                    valenceIndex.bind(to: documentManager)
                }
            }
        }
    }

    private var bottomToolbarHeight: CGFloat {
        showsBottomToolbar ? toolbarHeight : 0
    }

    private var showsBottomToolbar: Bool {
        viewMode == .archive && !showsPreferences
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                withAnimation(Theme.navigationIn) {
                    showsPreferences = true
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color(uiColor: .label))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Highlights")
        }
    }

    private func makeVisibleViewport(from frames: [String: CGRect], viewportHeight: CGFloat) -> ArchiveMinimapViewport? {
        let totalScraps = documentManager.scraps.count
        guard totalScraps > 0, viewportHeight > 0 else { return nil }

        let minimapIndexByScrapID = Dictionary(
            uniqueKeysWithValues: documentManager.scraps.reversed().enumerated().map { index, scrap in
                (scrap.id, index)
            }
        )

        let sliceHeight = 1 / CGFloat(totalScraps)
        var minFraction = CGFloat.greatestFiniteMagnitude
        var maxFraction = CGFloat.leastNormalMagnitude

        for (id, frame) in frames {
            guard let index = minimapIndexByScrapID[id], frame.height > 0 else { continue }

            let visibleMinY = max(frame.minY, 0)
            let visibleMaxY = min(frame.maxY, viewportHeight)
            guard visibleMaxY > visibleMinY else { continue }

            let visibleStart = min(max((visibleMinY - frame.minY) / frame.height, 0), 1)
            let visibleEnd = min(max((visibleMaxY - frame.minY) / frame.height, 0), 1)
            let sliceTop = CGFloat(index) * sliceHeight

            minFraction = min(minFraction, sliceTop + visibleStart * sliceHeight)
            maxFraction = max(maxFraction, sliceTop + visibleEnd * sliceHeight)
        }

        guard minFraction.isFinite, maxFraction.isFinite, maxFraction > minFraction else { return nil }

        return ArchiveMinimapViewport(
            topFraction: min(max(minFraction, 0), 1),
            heightFraction: min(max(maxFraction - minFraction, 0), 1)
        )
    }

    private func scrollToArchiveScrap(_ id: String, proxy: ScrollViewProxy, animated: Bool) {
        archiveScrollViewStore.scrollView?.stopDeceleratingImmediately()

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
    }
}
