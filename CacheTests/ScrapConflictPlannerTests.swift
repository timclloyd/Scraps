import XCTest
@testable import Scraps

final class ScrapConflictPlannerTests: XCTestCase {
    func testPlansMergeForIndependentEditsWithBaseText() {
        let plan = ScrapConflictPlanner.plan(
            baseText: "one\ntwo\nthree\n",
            currentText: "one\nmac\nthree\n",
            conflictVersions: [
                .init(text: "one\ntwo\nphone\n", sourceDescription: "iPhone")
            ]
        )

        XCTAssertEqual(plan, .merged("one\nmac\nphone\n"))
    }

    func testPlansPreservedVersionForOverlappingEdits() {
        let version = ScrapConflictPlanner.Version(
            text: "one\nphone\nthree\n",
            sourceDescription: "iPhone"
        )

        let plan = ScrapConflictPlanner.plan(
            baseText: "one\ntwo\nthree\n",
            currentText: "one\nmac\nthree\n",
            conflictVersions: [version]
        )

        XCTAssertEqual(plan, .preserveVersions([version]))
    }

    func testPlansPreservedVersionWhenBaseIsUnavailable() {
        let version = ScrapConflictPlanner.Version(
            text: "phone text\n",
            sourceDescription: "iPhone"
        )

        let plan = ScrapConflictPlanner.plan(
            baseText: nil,
            currentText: "mac text\n",
            conflictVersions: [version]
        )

        XCTAssertEqual(plan, .preserveVersions([version]))
    }

    func testIgnoresConflictVersionThatMatchesCurrentText() {
        let plan = ScrapConflictPlanner.plan(
            baseText: "base\n",
            currentText: "same\n",
            conflictVersions: [
                .init(text: "same\n", sourceDescription: "iPhone")
            ]
        )

        XCTAssertEqual(plan, .noOp)
    }

    func testIgnoresConflictVersionAlreadyRepresentedInCurrentText() {
        let plan = ScrapConflictPlanner.plan(
            baseText: nil,
            currentText: """
            Things

            Added on phone

            Added on mac
            """,
            conflictVersions: [
                .init(
                    text: """
                    Things

                    Added on mac
                    """,
                    sourceDescription: "Mac"
                )
            ]
        )

        XCTAssertEqual(plan, .noOp)
    }

    func testDeduplicatesConflictVersionsByText() {
        let first = ScrapConflictPlanner.Version(text: "phone\n", sourceDescription: "iPhone")
        let second = ScrapConflictPlanner.Version(text: "phone\n", sourceDescription: "iPad")

        let plan = ScrapConflictPlanner.plan(
            baseText: nil,
            currentText: "mac\n",
            conflictVersions: [first, second]
        )

        XCTAssertEqual(plan, .preserveVersions([first]))
    }

    func testRecognizesLegacyPreservedConflictHeader() {
        let text = """
        Sync conflict preserved from scrap-2026-05-11-080000Z.txt
        Source: iPhone

        ---

        body
        """

        XCTAssertTrue(ScrapConflictPlanner.isPreservedConflictCopy(text: text))
    }

    func testRecognizesInlineGeneratedPreservedConflictSection() {
        let version = ScrapConflictPlanner.Version(text: "phone\n", sourceDescription: "iPhone")
        let text = ScrapConflictPlanner.appendingPreservedConflictSections(
            to: "mac\n",
            originalFilename: "scrap-2026-05-11-080000Z.txt",
            versions: [version]
        )

        XCTAssertTrue(ScrapConflictPlanner.containsPreservedConflict(text: text))
        XCTAssertTrue(text.contains("---\n\(ScrapConflictPlanner.preservedConflictHeaderPrefix)iPhone\n\nphone\n---"))
        XCTAssertFalse(text.contains("scrap-2026-05-11-080000Z.txt"))
        XCTAssertFalse(text.contains("Conflict-ID: "))
    }

    func testDoesNotAppendSamePreservedConflictVersionTwice() {
        let version = ScrapConflictPlanner.Version(text: "phone\n", sourceDescription: "iPhone")
        let once = ScrapConflictPlanner.appendingPreservedConflictSections(
            to: "mac\n",
            originalFilename: "scrap-2026-05-11-080000Z.txt",
            versions: [version]
        )
        let twice = ScrapConflictPlanner.appendingPreservedConflictSections(
            to: once,
            originalFilename: "scrap-2026-05-11-080000Z.txt",
            versions: [version]
        )

        XCTAssertEqual(twice, once)
    }

    func testDoesNotNestExistingPreservedConflictSections() {
        let alreadyPreservedText = """
        Things

        ---
        🔀 Sync conflict preserved from Mac

        old conflict
        ---

        Phone line
        """
        let text = ScrapConflictPlanner.appendingPreservedConflictSections(
            to: "Mac line\n",
            originalFilename: "scrap-2026-05-11-080000Z.txt",
            versions: [
                .init(text: alreadyPreservedText, sourceDescription: "iPhone")
            ]
        )

        XCTAssertTrue(text.contains("Things\n\n\nPhone line"))
        XCTAssertFalse(text.contains("old conflict"))
        XCTAssertEqual(text.components(separatedBy: "🔀 Sync conflict preserved from").count, 2)
    }

    func testDoesNotTreatPlainPrefixAsPreservedConflictCopyWithoutDivider() {
        XCTAssertFalse(ScrapConflictPlanner.isPreservedConflictCopy(
            text: "Sync conflict preserved from a thought I had"
        ))
    }
}
