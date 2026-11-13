import XCTest

// XCUIApplication/XCUIElement APIs are main-actor-isolated on newer SDKs
// (confirmed on CI, not reproduced on this machine's older toolchain);
// under Swift 6 strict concurrency a plain, nonisolated test method can't
// call them at all.
@MainActor
final class LibrePawUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesToTheLoginScreen() throws {
        let app = XCUIApplication()
        // See LibrePawApp.resetStateLaunchArgument, the UI test target
        // can't reference the app's own symbols directly.
        app.launchArguments = ["-UITestResetState"]
        app.launch()

        XCTAssertTrue(app.staticTexts["LibrePaw"].waitForExistence(timeout: 5))
    }
}
