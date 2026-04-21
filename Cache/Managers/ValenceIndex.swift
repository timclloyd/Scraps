//
//  ValenceIndex.swift
//  Cache
//
//  Computes per-scrap valence keyword hits for the archive minimap.
//  All three bands contribute: positive → green, negative → red, neutral → blue.
//
//  Observes each scrap's `TextDocument.objectWillChange` so a keystroke in any
//  scrap triggers a per-scrap recompute (not a full sweep). Full recompute
//  happens only when the scraps array itself changes (load, new scrap, delete).
//

import Foundation
import Combine

struct ValenceHit: Equatable {
    let band: ValenceBand
}

@MainActor
final class ValenceIndex: ObservableObject {
    @Published private(set) var hits: [String: [ValenceHit]] = [:]

    private var documentCancellables: [String: AnyCancellable] = [:]
    private var scrapsCancellable: AnyCancellable?
    private weak var documentManager: DocumentManager?

    private static let valenceKeywords: [HighlightKeyword] = HighlightPatterns.keywords

    func bind(to manager: DocumentManager) {
        guard documentManager !== manager else { return }
        documentManager = manager

        scrapsCancellable = manager.$scraps
            .sink { [weak self] scraps in
                Task { @MainActor in
                    self?.rebuild(for: scraps)
                }
            }
    }

    private func rebuild(for scraps: [Scrap]) {
        let liveIDs = Set(scraps.map { $0.id })

        // Drop cached hits and subscriptions for scraps that no longer exist.
        hits = hits.filter { liveIDs.contains($0.key) }
        documentCancellables = documentCancellables.filter { liveIDs.contains($0.key) }

        for scrap in scraps {
            hits[scrap.id] = Self.computeHits(in: scrap.document.text)

            if documentCancellables[scrap.id] == nil {
                let id = scrap.id
                let document = scrap.document
                documentCancellables[id] = document.objectWillChange
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self, weak document] _ in
                        guard let self, let document else { return }
                        // objectWillChange fires before the new value is assigned,
                        // so defer to the next runloop turn to read the updated text.
                        DispatchQueue.main.async {
                            self.hits[id] = Self.computeHits(in: document.text)
                        }
                    }
            }
        }
    }

    private static func computeHits(in text: String) -> [ValenceHit] {
        guard !text.isEmpty else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        var result: [ValenceHit] = []
        for keyword in valenceKeywords {
            keyword.regex.enumerateMatches(in: text, options: [], range: range) { _, _, _ in
                result.append(ValenceHit(band: keyword.band))
            }
        }
        return result
    }
}
