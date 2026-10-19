import Testing
import XCTest
@testable import Demo

/// XCTest, as most projects still have.
final class SignInTests: XCTestCase {
    func testWelcomesAValidEmail() {
        XCTAssertEqual(signInMessage(email: "gary@example.com", password: "secret1"), "Welcome, gary@example.com")
    }

    func testRejectsAShortPassword() {
        XCTAssertEqual(signInMessage(email: "gary@example.com", password: "abc"), "Invalid email or password")
    }
}

/// Swift Testing, as new projects have.
@Test func rejectsAnEmailWithoutAt() {
    #expect(signInMessage(email: "gary", password: "secret1") == "Invalid email or password")
}
