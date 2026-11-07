// SPDX-License-Identifier: GPL-3.0-or-later
import XCTest

final class OpenScaleUITests: XCTestCase {
    @MainActor func testRememberedScaleAutomaticSaveUndoAndReview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-scale"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let automatic = app.switches["Save settled readings automatically"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        XCTAssertEqual(automatic.value as? String, "0")
        // SwiftUI exposes the whole labeled row as the switch AX element.
        // Hit the trailing native switch, not the center of its long label.
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(automatic.value as? String, "1")
        app.tabBars.buttons["Weigh in"].tap()
        XCTAssertTrue(app.staticTexts["Your OKOK scale"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop"].exists, "Remembered scale starts listening without another search")
        capture("remembered-listening", app)
        app.buttons["Simulate weigh-in"].tap()
        XCTAssertTrue(app.buttons["Undo automatic save"].waitForExistence(timeout: 5))
        capture("automatically-saved", app)
        app.buttons["Undo automatic save"].tap()
        XCTAssertTrue(app.staticTexts["Automatic save undone. Step off and on again for a new weigh-in."].exists)
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["Your first measurement"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Weigh in"].tap()
        app.buttons["Replay final packet"].tap()
        XCTAssertFalse(app.buttons["Undo automatic save"].exists, "Undo must not resurrect a repeated packet")
        XCTAssertTrue(app.staticTexts["Already captured this reading. Step off and on again for a new weigh-in."].exists)
        app.tabBars.buttons["Settings"].tap()
        automatic.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        app.tabBars.buttons["Weigh in"].tap()
        app.buttons["Simulate weigh-in"].tap()
        XCTAssertTrue(app.buttons["Save measurement"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Listen for your scale"].isEnabled)
        capture("review-before-save", app)
        app.buttons["Save measurement"].tap()
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["75.5 kg"].waitForExistence(timeout: 5))
    }
    @MainActor func testRememberedListeningInDarkLargeText() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-scale", "--ui-testing-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.tabBars.buttons["Weigh in"].tap()
        XCTAssertTrue(app.staticTexts["Waiting for your scale"].waitForExistence(timeout: 10))
        capture("remembered-dark-large-type", app)
    }
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
