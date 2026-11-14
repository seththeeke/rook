import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToBrandedRoot() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.otherElements["root.brand"].waitForExistence(timeout: 10))
    }
}
