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
    @State private var visibleViewport: ArchiveMinimapViewport? = nil
    let keyboardHeight: CGFloat
    let editorFont: UIFont
    var viewMode: ViewMode = .archive
    var searchQuery: String = ""
    var activeMatchScrapID: String? = nil
    var activeMatchRange: NSRange? = nil

    private static let archiveScrollCoordinateSpace = "ArchiveScrollCoordinateSpace"

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewportGeometry in
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
                        .padding(.trailing, Theme.minimapWidth)
                    }
                    .coordinateSpace(name: Self.archiveScrollCoordinateSpace)
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
                    .onPreferenceChange(ScrapFramePreferenceKey.self) { frames in
                        visibleViewport = makeVisibleViewport(
                            from: frames,
                            viewportHeight: viewportGeometry.size.height
                        )
                    }

                    ArchiveMinimapView(
                        scraps: documentManager.scraps,
                        hits: valenceIndex.hits,
                        visibleViewport: visibleViewport,
                        onTapScrap: { id in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(id, anchor: .top)
                            }
                        },
                        onScrubScrap: { id in
                            proxy.scrollTo(id, anchor: .top)
                        }
                    )
                    .padding(.top, Theme.textSize + 2)
                    .padding(.bottom, Theme.bottomFadeHeight)
                }
                .onAppear {
                    valenceIndex.bind(to: documentManager)
                }
            }
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
}
