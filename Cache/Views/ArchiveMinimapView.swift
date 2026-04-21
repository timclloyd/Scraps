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
//    - Opacity encodes hit count: 1 hit → 0.2, 5+ hits → 0.6.
//    - A scrap with no hits → empty slice.
//    - Every slice is a direct tap/scrub target — no empty days between rows.
//
//  Tap target extends beyond the visual strip (see `Theme.minimapTapWidth`) so
//  the strip stays narrow while remaining easy to hit.
//

import SwiftUI

private struct BandSegment {
    let band: ValenceBand
    let opacity: CGFloat
}

private struct Slice: Identifiable {
    let id: String          // scrap.id — doubles as the scroll target
    let segments: [BandSegment]
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
                        guard !slice.segments.isEmpty else { continue }
                        let sliceY = CGFloat(index) * h
                        let segH = h / CGFloat(slice.segments.count)
                        for (segIndex, segment) in slice.segments.enumerated() {
                            let rect = CGRect(
                                x: 0, y: sliceY + CGFloat(segIndex) * segH,
                                width: size.width, height: segH
                            )
                            context.fill(Path(rect), with: .color(Theme.minimapColor(for: segment.band).opacity(segment.opacity)))
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
            Slice(id: scrap.id, segments: Self.bandSegments(from: hits[scrap.id] ?? []))
        }
    }

    private static let opacityMin: CGFloat = 0.5
    private static let opacityMax: CGFloat = 1.0
    private static let opacityCountCap = 4

    /// One segment per distinct band, opacity scaled by hit count (1 hit → 0.2, 5+ hits → 0.6).
    private static func bandSegments(from hits: [ValenceHit]) -> [BandSegment] {
        var counts: [ValenceBand: Int] = [:]
        var order: [ValenceBand] = []
        for hit in hits {
            if counts[hit.band] == nil { order.append(hit.band) }
            counts[hit.band, default: 0] += 1
        }
        return order.map { band in
            let count = counts[band] ?? 1
            let t = min(CGFloat(count - 1) / CGFloat(opacityCountCap - 1), 1.0)
            return BandSegment(band: band, opacity: opacityMin + t * (opacityMax - opacityMin))
        }
    }
}
