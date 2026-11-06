import XCTest

final class ScentrailUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesToTheLoginScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Scentrail"].waitForExistence(timeout: 5))
    }
}
