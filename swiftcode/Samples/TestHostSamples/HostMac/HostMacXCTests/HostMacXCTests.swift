import XCTest
@testable import HostMac

final class HostMacXCTests: XCTestCase {
    func testAddsInTheApp() {
        XCTAssertEqual(Arithmetic.add(2, 3), 5)
    }

    @MainActor
    func testRunsAfterLaunch() {
        XCTAssertTrue(LaunchState.launched)
        XCTAssertNotNil(NSApplication.shared.delegate)
    }

    func testPlanEnvironment() {
        XCTAssertNotNil(ProcessInfo.processInfo.environment["HOSTMAC_PLAN"])
        XCTAssertNil(ProcessInfo.processInfo.environment["HOSTMAC_UNUSED"])
    }

    func testFailsOnPurpose() {
        XCTAssertEqual(Arithmetic.add(2, 2), 5, "fails as written")
    }

    func testSkipped() throws {
        throw XCTSkip("skipped as written")
    }
}
