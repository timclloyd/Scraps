import XCTest
@testable import Scraps

final class StrikethroughLineMutationTests: XCTestCase {
    func testRightSwipeWrapsPlainLine() {
        let result = StrikethroughLineMutation.result(for: "todo item\n", isRightSwipe: true)

        XCTAssertEqual(result?.replacement, "~~todo item~~\n")
    }

    func testLeftSwipeUnwrapsStruckLine() {
        let result = StrikethroughLineMutation.result(for: "~~todo item~~\n", isRightSwipe: false)

        XCTAssertEqual(result?.replacement, "todo item\n")
    }

    func testIgnoresAlreadyStruckRightSwipeAndPlainLeftSwipe() {
        XCTAssertNil(StrikethroughLineMutation.result(for: "~~todo item~~\n", isRightSwipe: true))
        XCTAssertNil(StrikethroughLineMutation.result(for: "todo item\n", isRightSwipe: false))
    }
}
