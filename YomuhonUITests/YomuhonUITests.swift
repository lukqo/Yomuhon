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
        let app = makeApp()
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 8),
            "Yomuhon should present its primary window on every supported destination."
        )
    }

    func testPrimaryNavigationIsReachable() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(searchNavigationButton(in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Downloads", "Descargas")
            ).firstMatch.exists
        )
    }

    func testSearchDetailReaderFlowUsesDeterministicFixture() throws {
        let app = makeApp()
        app.launch()

        openFixtureManga(in: app)

        let readerButton = element("reader.open.ui-test-chapter-1", in: app)
        XCTAssertTrue(readerButton.waitForExistence(timeout: 5))
        readerButton.tap()

        XCTAssertTrue(element("reader.close", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("reader.content.remote", in: app).waitForExistence(timeout: 5))
    }

    func testDownloadedChapterOpensWithLocalPages() throws {
        let app = makeApp()
        app.launch()

        openFixtureManga(in: app)

        let downloadMenu = element("detail.download.menu", in: app)
        XCTAssertTrue(downloadMenu.waitForExistence(timeout: 5))
        downloadMenu.tap()

        let downloadChapter = element("detail.download.chapter", in: app)
        XCTAssertTrue(downloadChapter.waitForExistence(timeout: 3))
        downloadChapter.tap()

        let deadline = Date().addingTimeInterval(5)
        var isDownloaded = false
        while Date() < deadline && !isDownloaded {
            downloadMenu.tap()
            let option = element("detail.download.chapter", in: app)
            if option.waitForExistence(timeout: 0.4) {
                let label = option.label
                if label == "Downloaded" || label == "Descargado" {
                    isDownloaded = true
                    break
                }
            }
            if option.exists {
                downloadMenu.tap()
            }
        }
        XCTAssertTrue(isDownloaded, "The fixture chapter should become downloaded.")

        let readerButton = element("reader.open.ui-test-chapter-1", in: app)
        XCTAssertTrue(readerButton.waitForExistence(timeout: 5))
        readerButton.tap()

        XCTAssertTrue(element("reader.content.local", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("reader.close", in: app).exists)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                makeApp().launch()
            }
        }
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        return app
    }

    private func openFixtureManga(in app: XCUIApplication) {
        let search = searchNavigationButton(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()

        let field = element("search.field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("fixture")

        let manga = element("manga.open.ui-test-manga", in: app)
        XCTAssertTrue(manga.waitForExistence(timeout: 5))
        manga.tap()
    }

    private func searchNavigationButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Search", "Buscar")
        ).firstMatch
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
    }
}
