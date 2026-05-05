import XCTest
@testable import Scraps

final class HighlightPatternsTests: XCTestCase {
    func testRangeIntersectsStrikeForTextInsideStrikeMarkers() {
        let text = "keep idea ~~ignore idea~~ keep todo"
        let nsText = text as NSString
        let strikeRanges = HighlightPatterns.strikeRanges(in: text)

        let crossedOutText = nsText.range(of: "ignore idea")
        let crossedOutIdea = nsText.range(of: "idea", options: [], range: crossedOutText)
        let visibleIdea = nsText.range(of: "idea")

        XCTAssertFalse(HighlightPatterns.rangeIntersectsStrike(visibleIdea, strikeRanges: strikeRanges))
        XCTAssertTrue(HighlightPatterns.rangeIntersectsStrike(crossedOutIdea, strikeRanges: strikeRanges))
    }
}
