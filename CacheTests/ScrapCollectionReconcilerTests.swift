import XCTest
@testable import Scraps

@MainActor
final class ScrapCollectionReconcilerTests: XCTestCase {
    func testReconcilePreservesExistingScrapForDuplicateLoadedScrap() throws {
        let existing = try makeScrap(named: "scrap-2026-04-29-100000Z.txt")
        let duplicate = try makeScrap(named: "scrap-2026-04-29-100000Z.txt")

        let result = ScrapCollectionReconciler.reconcile(
            currentScraps: [existing],
            loadedScraps: [duplicate]
        )

        XCTAssertEqual(result.scraps.map(\.id), [existing.id])
        XCTAssertTrue(result.scraps[0].document === existing.document)
        XCTAssertEqual(result.addedScraps.map(\.id), [])
        XCTAssertEqual(result.removedScraps.map(\.id), [])
        XCTAssertEqual(result.duplicateScraps.map(\.id), [duplicate.id])
    }

    func testReconcileAddsNewScrapsInTimestampOrder() throws {
        let middle = try makeScrap(named: "scrap-2026-04-29-100000Z.txt")
        let newest = try makeScrap(named: "scrap-2026-04-29-120000Z.txt")
        let oldest = try makeScrap(named: "scrap-2026-04-29-080000Z.txt")

        let result = ScrapCollectionReconciler.reconcile(
            currentScraps: [middle],
            loadedScraps: [newest, oldest, middle]
        )

        XCTAssertEqual(result.scraps.map(\.id), [oldest.id, middle.id, newest.id])
        XCTAssertEqual(result.addedScraps.map(\.id), [oldest.id, newest.id])
        XCTAssertEqual(result.removedScraps.map(\.id), [])
        XCTAssertEqual(result.duplicateScraps.map(\.id), [middle.id])
    }

    func testReconcileReportsRemovedScrapsWhenLoadedSetIsEmpty() throws {
        let first = try makeScrap(named: "scrap-2026-04-29-080000Z.txt")
        let second = try makeScrap(named: "scrap-2026-04-29-090000Z.txt")

        let result = ScrapCollectionReconciler.reconcile(
            currentScraps: [first, second],
            loadedScraps: []
        )

        XCTAssertEqual(result.scraps.map(\.id), [])
        XCTAssertEqual(result.addedScraps.map(\.id), [])
        XCTAssertEqual(result.removedScraps.map(\.id), [first.id, second.id])
        XCTAssertEqual(result.duplicateScraps.map(\.id), [])
    }

    private func makeScrap(named filename: String) throws -> Scrap {
        let timestamp = try XCTUnwrap(Scrap.parseTimestamp(from: filename))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        let document = TextDocument(fileURL: url)
        return Scrap(timestamp: timestamp, filename: filename, document: document)
    }
}
