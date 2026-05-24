import XCTest

final class HabitTrackerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingScreenAppearsOnFreshLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitesting"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Build streaks that feel calm, not punishing."].waitForExistence(timeout: 2))
    }
}
