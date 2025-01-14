//
//  UITests.swift
//  CacheTests
//
//  Created by Tim Lloyd on 2025-01-13.
//

import XCTest

final class UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        
        // This measures how long it takes to launch your application
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            // Wait for the app to be ready
            XCTAssert(app.exists)
            app.terminate()
        }
    }
}
