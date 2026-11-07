import XCTest

final class HostMacUITests: XCTestCase {
    func testRunnerStarts() {
        XCTAssertEqual(1 + 1, 2)
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
