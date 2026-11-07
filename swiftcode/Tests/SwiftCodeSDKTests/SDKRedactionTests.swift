import XCTest
@testable import SwiftCodeSDK

final class SDKRedactionTests: XCTestCase {
    func testRedactsDeveloperAPIKey() {
        let text = "failed with key sc_dev_live_abc123.def456"
        let redacted = SDKLogRedaction.redactSecrets(text)
        XCTAssertFalse(redacted.contains("sc_dev_live_"))
        XCTAssertTrue(redacted.contains("<redacted-api-key>"))
    }

    func testRedactsGitHubToken() {
        let redacted = SDKLogRedaction.redactSecrets("token ghp_abcdefghij1234567890")
        XCTAssertFalse(redacted.contains("ghp_"))
        XCTAssertTrue(redacted.contains("<redacted-token>"))
    }

    func testRedactsPEMBlock() {
        let pem = "-----BEGIN " + "PRIVATE KEY-----\nMIIEvQIBADANBg==\n-----END " + "PRIVATE KEY-----"
        XCTAssertEqual(SDKLogRedaction.redactSecrets(pem), "<redacted-pem>")
    }

    func testSanitizeCollapsesPathsAndAddresses() {
        let text = "error at /Users/user/Projects/App.swift:10 and 0x00007f8a1b2c3d4e"
        let sanitized = SDKLogRedaction.sanitizeForUser(text)
        XCTAssertFalse(sanitized.contains("/Users/user"))
        XCTAssertFalse(sanitized.contains("0x00007f8a1b2c3d4e"))
        XCTAssertTrue(sanitized.contains("<path>"))
        XCTAssertTrue(sanitized.contains("<address>"))
    }

    func testRedactDiagnosticValueByKey() {
        XCTAssertEqual(SDKLogRedaction.redactDiagnosticValue(key: "password", value: "hunter2"), "<redacted>")
        XCTAssertEqual(SDKLogRedaction.redactDiagnosticValue(key: "apiKey", value: "abc"), "<redacted>")
        XCTAssertEqual(SDKLogRedaction.redactDiagnosticValue(key: "accessToken", value: "abc"), "<redacted>")
        XCTAssertEqual(SDKLogRedaction.redactDiagnosticValue(key: "message", value: "hello"), "hello")
    }

    func testUserLoggerSanitizesEntries() {
        let logger = SDKUserLogger.shared
        logger.clear()
        logger.logInfo("key sc_dev_test_abc.def", title: "Test")
        let entries = logger.recentEntries(limit: 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].message.contains("sc_dev_test_"))
    }
}
