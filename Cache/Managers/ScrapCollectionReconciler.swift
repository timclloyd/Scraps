import Foundation

@MainActor
enum ScrapCollectionReconciler {
    struct Result {
        let scraps: [Scrap]
        let addedScraps: [Scrap]
        let removedScraps: [Scrap]
        let duplicateScraps: [Scrap]
    }

    static func reconcile(currentScraps: [Scrap], loadedScraps: [Scrap]) -> Result {
        let currentIDs = Set(currentScraps.map { $0.id })
        let loadedIDs = Set(loadedScraps.map { $0.id })

        let addedScraps = loadedScraps
            .filter { !currentIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
        let removedScraps = currentScraps.filter { !loadedIDs.contains($0.id) }
        let duplicateScraps = loadedScraps.filter { currentIDs.contains($0.id) }

        var reconciledScraps = currentScraps.filter { loadedIDs.contains($0.id) }
        for newScrap in addedScraps {
            if let index = reconciledScraps.firstIndex(where: { $0.timestamp > newScrap.timestamp }) {
                reconciledScraps.insert(newScrap, at: index)
            } else {
                reconciledScraps.append(newScrap)
            }
        }

        return Result(
            scraps: reconciledScraps,
            addedScraps: addedScraps,
            removedScraps: removedScraps,
            duplicateScraps: duplicateScraps
        )
    }
}
