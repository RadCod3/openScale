// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class OpenScaleUITests: XCTestCase {
    @MainActor func testManualEntryAndNativeScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Your first measurement"].waitForExistence(timeout: 10))
        capture("journal-empty", app)
        app.buttons["Add measurement"].firstMatch.tap()
        let weight = app.textFields["Weight in kg"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        weight.tap(); weight.typeText("75.5")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Measurement saved."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["75.5 kg"].exists)
        capture("journal-saved", app)
        app.tabBars.buttons["Weigh in"].tap()
        XCTAssertTrue(app.buttons["Search for my scale"].waitForExistence(timeout: 5))
        capture("weigh-in", app)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Import Android CSV"].waitForExistence(timeout: 5))
        app.buttons["Set up your profile"].tap()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Me"].waitForExistence(timeout: 5))
        capture("settings", app)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-testing-seed", "--ui-testing-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Measurements"].waitForExistence(timeout: 10))
        capture("journal-dark-large-type", app)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
