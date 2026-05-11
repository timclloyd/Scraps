import XCTest
@testable import Scraps

final class TextMergeTests: XCTestCase {
    func testMergesIndependentLineEdits() {
        let base = """
        alpha
        beta
        gamma
        """
        let current = """
        alpha
        beta on mac
        gamma
        """
        let incoming = """
        alpha
        beta
        gamma on phone
        """

        let result = TextMerge.conservativeThreeWayMerge(
            base: base,
            current: current,
            incoming: incoming
        )

        XCTAssertEqual(result, .merged("""
        alpha
        beta on mac
        gamma on phone
        """))
    }

    func testRefusesOverlappingLineEdits() {
        let result = TextMerge.conservativeThreeWayMerge(
            base: "alpha\nbeta\ngamma\n",
            current: "alpha\nbeta on mac\ngamma\n",
            incoming: "alpha\nbeta on phone\ngamma\n"
        )

        XCTAssertEqual(result, .conflict)
    }

    func testKeepsCurrentWhenIncomingDidNotChangeFromBase() {
        let result = TextMerge.conservativeThreeWayMerge(
            base: "alpha\n",
            current: "alpha\nmac\n",
            incoming: "alpha\n"
        )

        XCTAssertEqual(result, .merged("alpha\nmac\n"))
    }

    func testMergesConcurrentInsertionsAtSameLocationByPreservingBoth() {
        let result = TextMerge.conservativeThreeWayMerge(
            base: "alpha\ngamma\n",
            current: "alpha\nmac\ngamma\n",
            incoming: "alpha\nphone\ngamma\n"
        )

        XCTAssertEqual(result, .merged("alpha\nmac\nphone\ngamma\n"))
    }
}
