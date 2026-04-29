import XCTest
import UIKit
@testable import Scraps

final class ScrapCreationPolicyTests: XCTestCase {
    func testShouldCreateNewScrapReturnsFalseWithoutLatestTimestamp() {
        XCTAssertFalse(ScrapCreationPolicy.shouldCreateNewScrap(latestTimestamp: nil))
    }

    func testShouldCreateNewScrapUsesInjectedCalendarDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        let latest = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 29,
            hour: 23,
            minute: 59
        ).date)
        let sameDay = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 29,
            hour: 8
        ).date)
        let nextDay = try XCTUnwrap(DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 4,
            day: 30,
            hour: 0
        ).date)

        XCTAssertFalse(ScrapCreationPolicy.shouldCreateNewScrap(
            latestTimestamp: latest,
            now: sameDay,
            calendar: calendar
        ))
        XCTAssertTrue(ScrapCreationPolicy.shouldCreateNewScrap(
            latestTimestamp: latest,
            now: nextDay,
            calendar: calendar
        ))
    }

    func testIsSafelyEmptyRequiresBlankTextAndNonTransferringState() {
        XCTAssertTrue(ScrapCreationPolicy.isSafelyEmpty(text: " \n\t", documentState: []))
        XCTAssertFalse(ScrapCreationPolicy.isSafelyEmpty(text: "note", documentState: []))
        XCTAssertFalse(ScrapCreationPolicy.isSafelyEmpty(text: "", documentState: .progressAvailable))
        XCTAssertFalse(ScrapCreationPolicy.isSafelyEmpty(text: "", documentState: .editingDisabled))
        XCTAssertFalse(ScrapCreationPolicy.isSafelyEmpty(text: "", documentState: .inConflict))
    }
}
