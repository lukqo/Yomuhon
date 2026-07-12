//
//  YomuhonUITests.swift
//  YomuhonUITests
//

import XCTest

final class YomuhonUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsPrimaryInterface() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 8),
            "Yomuhon should present its primary window on every supported destination."
        )
    }

    func testPrimaryNavigationIsReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let search = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Search", "Buscar")
        ).firstMatch
        let downloads = app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Downloads", "Descargas")
        ).firstMatch

        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertTrue(downloads.exists)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
