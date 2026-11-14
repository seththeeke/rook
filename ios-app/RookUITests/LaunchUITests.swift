import XCTest

/// Smoke tests that need no account: a fresh install lands on sign-in and validates input locally.
final class LaunchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testFreshInstallShowsSignIn() {
        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["auth.title"].label, "Welcome to Rook")
        XCTAssertTrue(app.buttons["auth.submit"].exists)
    }

    @MainActor
    func testInvalidEmailIsCaughtBeforeContactingServer() {
        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 15))
        let email = app.textFields["auth.email"]
        email.tap()
        email.typeText("not-an-email")
        app.buttons["auth.submit"].tap()
        let error = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "valid email address")).firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    func testCanNavigateToSignUpAndSeePasswordRules() {
        XCTAssertTrue(app.staticTexts["auth.title"].waitForExistence(timeout: 15))
        app.buttons["Create an account"].tap()
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["At least 8 characters"].exists || app.otherElements["At least 8 characters, not met"].exists
            || app.descendants(matching: .any)["At least 8 characters, not met"].exists)
    }
}
