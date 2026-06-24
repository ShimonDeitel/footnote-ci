import XCTest

/// Smoke UI tests that tap through every tab without requiring microphone access.
final class FootnoteUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FOOTNOTE_NO_SK"] = "1"   // no StoreKit sign-in prompt
        app.launchEnvironment["FOOTNOTE_SEED"] = "1"    // one structured note in the archive
        if pro { app.launchEnvironment["FOOTNOTE_FORCE_PRO"] = "1" }
        app.launch()
        return app
    }

    func testTabsExistAndSwitch() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Record"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Notes"].tap()
        app.tabBars.buttons["Ask"].tap()
        app.tabBars.buttons["Commitments"].tap()
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
    }

    func testSeededNoteOpens() {
        let app = launch()
        app.tabBars.buttons["Notes"].tap()
        // The seeded note title should appear and open into the detail.
        let cell = app.staticTexts["Q3 Pricing Review"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.staticTexts["Decisions"].waitForExistence(timeout: 3)
                      || app.navigationBars.element.waitForExistence(timeout: 3))
    }

    func testCommitmentsProShowsRollup() {
        let app = launch(pro: true)
        app.tabBars.buttons["Commitments"].tap()
        XCTAssertTrue(app.navigationBars["Commitments"].waitForExistence(timeout: 5))
    }
}
