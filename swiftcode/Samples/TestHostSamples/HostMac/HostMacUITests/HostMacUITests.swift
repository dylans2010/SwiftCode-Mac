import XCTest

/// A UI test bundle. SwiftCode runs it in its own runner; tests that drive the
/// app through XCUIApplication need the reference's automation service,
/// which SwiftCode does not provide (specs/ide/testing.md, "SwiftCode implementation").
final class HostMacUITests: XCTestCase {
    func testRunnerStarts() {
        XCTAssertEqual(1 + 1, 2)
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
