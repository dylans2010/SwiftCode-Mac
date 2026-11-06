import XCTest
import SwiftCodeExtensions
@testable import SwiftCodeSDK

/// Manifest validation through the existing strict validator
/// (`SwiftCodeManifestValidator`) — the SDK host never runs a second
/// validator.
final class SDKManifestValidationTests: XCTestCase {
    private func validManifestJSON(capabilities: [[String: String]] = [["id": "docs.search", "reason": "Open docs."]]) -> Data {
        let object: [String: Any] = [
            "manifestVersion": 1,
            "id": "com.example.test",
            "name": "Test Extension",
            "version": "1.0.0",
            "type": "extension",
            "runtime": ["language": "typescript", "entrypoint": "dist/index.js", "minimumSwiftCodeVersion": "1.0.0"],
            "sdk": ["name": "@swiftcode/sdk", "versionRange": "^1.0.0", "protocolVersion": 1],
            "capabilities": capabilities,
            "assist": ["requested": false],
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testValidManifestPasses() throws {
        let manifest = try SwiftCodeManifestValidator.validate(data: validManifestJSON())
        XCTAssertEqual(manifest.id, "com.example.test")
        XCTAssertEqual(manifest.version, "1.0.0")
    }

    func testUnknownCapabilityFails() {
        let data = validManifestJSON(capabilities: [["id": "nope.not-a-capability", "reason": "x"]])
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(data: data))
    }

    func testMalformedJSONFails() {
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(data: Data("not json".utf8)))
    }

    func testOversizeManifestFails() {
        let padding = String(repeating: "x", count: 70_000)
        let data = Data("{\"manifestVersion\":1,\"id\":\"\(padding)\"}".utf8)
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(data: data))
    }

    func testAssistCapabilityIsKnownToValidatorButRestrictedInRegistry() throws {
        let manifest = try SwiftCodeManifestValidator.validate(
            data: validManifestJSON(capabilities: [["id": "assist.invoke", "reason": "Assist."]])
        )
        XCTAssertEqual(manifest.capabilities.first?.id, "assist.invoke")
        // The validator knows the ID; the host registry refuses to grant it.
        XCTAssertFalse(SDKCapabilityRegistry.info(for: .assistInvoke).grantableInCurrentRelease)
    }
}
