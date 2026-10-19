import XCTest

/// Captures App Store screenshots. Run with scripts/screenshots.sh KitchenTempLog.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAppScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-unlock", "-resetData", "-sampleData", "-skipOnboarding", "-uiTesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Walk-in cooler"].firstMatch.waitForExistence(timeout: 15))
        snap("01-today", app)

        // The midday hot well has no reading yet, so this opens a fresh entry rather than an edit.
        app.staticTexts["Hot well, soup"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Log Reading"].waitForExistence(timeout: 5))
        app.typeText("120")
        XCTAssertTrue(app.staticTexts["Outside the limit"].waitForExistence(timeout: 5))
        app.buttons["Reheated to the required temperature"].tap()
        app.buttons["Done"].firstMatch.tap()          // drop the number pad so the whole form shows
        snap("02-out-of-range", app)
        app.buttons["Cancel"].tap()

        tab("Cooling", app)
        XCTAssertTrue(app.navigationBars["Cooling"].waitForExistence(timeout: 5))
        snap("03-cooling", app)

        app.staticTexts["Chili"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Chili"].waitForExistence(timeout: 5))
        snap("04-cooling-batch", app)

        tab("Log", app)
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5))
        sleep(2)   // let the chart settle before the shutter
        snap("05-log", app)

        tab("Setup", app)
        XCTAssertTrue(app.navigationBars["Setup"].waitForExistence(timeout: 5))
        snap("06-setup", app)
    }

    func testPaywall() {
        let app = XCUIApplication()
        app.launchArguments = ["-skipOnboarding", "-uiTesting", "-mockPrices"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Lifetime"].waitForExistence(timeout: 10))
        snap("paywall", app)
    }

    /// iPhone shows a bottom tab bar; iPad shows a floating segmented control.
    private func tab(_ name: String, _ app: XCUIApplication) {
        let inTabBar = app.tabBars.buttons[name]
        if inTabBar.waitForExistence(timeout: 2) { inTabBar.tap() } else { app.buttons[name].firstMatch.tap() }
    }

    private func snap(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
