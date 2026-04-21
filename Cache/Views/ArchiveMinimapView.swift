//
//  ArchiveMinimapView.swift
//  Cache
//
//  Thin vertical strip along the archive's trailing edge that renders each
//  scrap's valence composition as colour. See the v1 PRD
//  (`Documentation/PRDs/2026-04-PRD-valence-minimap.md`) for design rationale.
//
//  Rendering model — one row per scrap:
//    - Each scrap gets an equal vertical slice (newest at top, oldest at bottom).
//    - A scrap with valence hits → Canvas draws one coloured rect per distinct
//      band. At most three segments (positive / negative / neutral).
//    - A scrap with no hits → empty slice.
//    - Every slice is a direct tap/scrub target — no empty days between rows.
//
//  Tap target extends beyond the visual strip (see `Theme.minimapTapWidth`) so
//  the strip stays narrow while remaining easy to hit.
//

import SwiftUI

private struct Slice: Identifiable {
    let id: String          // scrap.id — doubles as the scroll target
    let bands: [ValenceBand]
}

struct ArchiveMinimapView: View {
    let scraps: [Scrap]
    let hits: [String: [ValenceHit]]
    /// Called on tap/drag-release so the archive can animate to the scrap.
    let onTapScrap: (String) -> Void
    /// Called continuously while dragging for immediate (non-animated) scrubbing.
    let onScrubScrap: (String) -> Void

    @State private var activeDragSlice: Int? = nil

    var body: some View {
        let slices = buildSlices()

        GeometryReader { geometry in
            let sliceHeight = slices.isEmpty ? 0 : geometry.size.height / CGFloat(slices.count)

            ZStack(alignment: .trailing) {
                Color.clear
                Canvas { context, size in
                    guard !slices.isEmpty else { return }
                    let h = size.height / CGFloat(slices.count)
                    for (index, slice) in slices.enumerated() {
                        guard !slice.bands.isEmpty else { continue }
                        let sliceY = CGFloat(index) * h
                        let segH = h / CGFloat(slice.bands.count)
                        for (bandIndex, band) in slice.bands.enumerated() {
                            let rect = CGRect(
                                x: 0, y: sliceY + CGFloat(bandIndex) * segH,
                                width: size.width, height: segH
                            )
                            context.fill(Path(rect), with: .color(Theme.minimapColor(for: band)))
                        }
                    }
                }
                .frame(width: Theme.minimapWidth)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !slices.isEmpty, sliceHeight > 0 else { return }
                        let clamped = min(max(value.location.y, 0), geometry.size.height - 0.001)
                        let index = min(Int(clamped / sliceHeight), slices.count - 1)
                        guard index != activeDragSlice else { return }
                        activeDragSlice = index
                        onScrubScrap(slices[index].id)
                    }
                    .onEnded { value in
                        activeDragSlice = nil
                        guard !slices.isEmpty, sliceHeight > 0 else { return }
                        let clamped = min(max(value.location.y, 0), geometry.size.height - 0.001)
                        let index = min(Int(clamped / sliceHeight), slices.count - 1)
                        onTapScrap(slices[index].id)
                    }
            )
        }
        .frame(width: Theme.minimapTapWidth)
    }

    /// One slice per scrap, newest first. scraps is sorted oldest-first by DocumentManager.
    private func buildSlices() -> [Slice] {
        scraps.reversed().map { scrap in
            Slice(id: scrap.id, bands: Self.distinctBands(from: hits[scrap.id] ?? []))
        }
    }

    /// Dedup hits by band, preserving first-seen order. At most three segments per scrap.
    private static func distinctBands(from hits: [ValenceHit]) -> [ValenceBand] {
        var seen: Set<ValenceBand> = []
        var result: [ValenceBand] = []
        for hit in hits {
            if seen.insert(hit.band).inserted {
                result.append(hit.band)
            }
        }
        return result
    }
}
