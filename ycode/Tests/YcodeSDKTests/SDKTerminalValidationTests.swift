import XCTest
@testable import YcodeSDK

/// Sandboxed terminal validation (the pure core ported from Legacy's
/// `sandbox_validation_test.py`): allow-list, argument limits, and cwd
/// confinement. No process is ever spawned here.
final class SDKTerminalValidationTests: XCTestCase {
    func testAllowedBareNamesResolve() throws {
        // `ls` exists in /bin on both macOS and Linux.
        let path = try SDKSandboxedTerminal.resolveExecutable("ls")
        XCTAssertTrue(path.hasSuffix("/ls"))
    }

    func testShellNamesAreRejected() {
        for shell in ["sh", "bash", "zsh", "env"] {
            XCTAssertThrowsError(try SDKSandboxedTerminal.resolveExecutable(shell)) { error in
                XCTAssertEqual((error as? SDKError)?.code, .permissionDenied)
            }
        }
    }

    func testUnknownCommandIsRejected() {
        XCTAssertThrowsError(try SDKSandboxedTerminal.resolveExecutable("definitely-not-a-real-command")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .permissionDenied)
        }
    }

    func testAbsolutePathOutsideApprovedDirsIsRejected() {
        XCTAssertThrowsError(try SDKSandboxedTerminal.resolveExecutable("/tmp/ls")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .permissionDenied)
        }
    }

    func testArgumentLimits() {
        XCTAssertThrowsError(try SDKSandboxedTerminal.validateArguments(Array(repeating: "x", count: 257))) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
        XCTAssertThrowsError(try SDKSandboxedTerminal.validateArguments([String(repeating: "x", count: 8_193)])) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
        XCTAssertNoThrow(try SDKSandboxedTerminal.validateArguments(["--help"]))
    }

    func testWorkingDirectoryConfinement() throws {
        let root = FileManager.default.temporaryDirectory.path
        // Default is the scope root.
        XCTAssertEqual(try SDKSandboxedTerminal.resolveWorkingDirectory(nil, scopeRoot: root), root)
        // An explicit directory inside the scope is fine.
        let inside = (root as NSString).appendingPathComponent("subdir")
        try FileManager.default.createDirectory(atPath: inside, withIntermediateDirectories: true)
        XCTAssertEqual(try SDKSandboxedTerminal.resolveWorkingDirectory(inside, scopeRoot: root), inside)
        // Outside the scope is rejected.
        XCTAssertThrowsError(try SDKSandboxedTerminal.resolveWorkingDirectory("/etc", scopeRoot: root)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .projectOutOfScope)
        }
        // `..` escape is rejected.
        XCTAssertThrowsError(try SDKSandboxedTerminal.resolveWorkingDirectory(root + "/../etc", scopeRoot: root)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .projectOutOfScope)
        }
    }
}
