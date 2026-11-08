import XCTest

final class LibrePawUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesToTheLoginScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["LibrePaw"].waitForExistence(timeout: 5))
    }
}
