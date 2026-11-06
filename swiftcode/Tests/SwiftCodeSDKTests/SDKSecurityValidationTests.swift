import XCTest
@testable import SwiftCodeSDK

/// Security ID / value ID / label validation and the KeychainSDK vault
/// round-trip (in-memory store in tests via the file store? No — the
/// vault uses the platform store; these tests cover validation only,
/// plus envelope behavior through a throwaway file store on Linux and
/// the Keychain on macOS is NOT touched: validation is pure).
final class SDKSecurityValidationTests: XCTestCase {
    func testValidSecurityIDs() {
        XCTAssertNoThrow(try KeychainSDK.validateSecurityID("com.example.app"))
        XCTAssertNoThrow(try KeychainSDK.validateSecurityID("com.swiftcode.sdk.security.test"))
    }

    func testInvalidSecurityIDs() {
        for bad in ["single", "com..example", "com/example", "com.example ", "", "a.b.c/d", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try KeychainSDK.validateSecurityID(bad), "\(bad)") { error in
                XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
            }
        }
    }

    func testValidValueIDs() {
        XCTAssertNoThrow(try KeychainSDK.validateValueID("api-key"))
        XCTAssertNoThrow(try KeychainSDK.validateValueID("tokens/github"))
        XCTAssertNoThrow(try KeychainSDK.validateValueID("a.b_c-d/e"))
    }

    func testInvalidValueIDs() {
        for bad in ["", "-leading", "trailing-", "has space", String(repeating: "a", count: 129)] {
            XCTAssertThrowsError(try KeychainSDK.validateValueID(bad), "\(bad)") { error in
                XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
            }
        }
    }

    func testLabelValidation() {
        XCTAssertNoThrow(try KeychainSDK.validateLabel("GitHub token"))
        XCTAssertThrowsError(try KeychainSDK.validateLabel("")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
        XCTAssertThrowsError(try KeychainSDK.validateLabel("has\0nul")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
    }

    func testCommandDefinitionValidation() {
        XCTAssertNoThrow(try SDKCommandDefinition.validate(id: "my-command", title: "My Command"))
        for bad in ["My-Command", "1abc", "has space", "has_underscore", String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try SDKCommandDefinition.validate(id: bad, title: "x"), "\(bad)") { error in
                XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
            }
        }
        XCTAssertThrowsError(try SDKCommandDefinition.validate(id: "ok", title: "")) { error in
            XCTAssertEqual((error as? SDKError)?.code, .invalidArgument)
        }
    }
}
