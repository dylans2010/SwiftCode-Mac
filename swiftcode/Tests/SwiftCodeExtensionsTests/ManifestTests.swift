import XCTest
@testable import SwiftCodeExtensions

final class ManifestTests: XCTestCase {
    private func packageJSON(_ overrides: [String: Any] = [:]) -> Data {
        var dict: [String: Any] = [
            "name": "sample",
            "publisher": "acme",
            "version": "1.2.3",
            "displayName": "Sample",
            "description": "A sample extension.",
            "engines": ["vscode": "^1.80.0"],
            "main": "./dist/index.js",
            "activationEvents": ["onCommand:acme.hello"],
            "extensionDependencies": ["other.dep"],
            "contributes": [
                "commands": [["command": "acme.hello", "title": "Hello"]],
                "views": ["explorer": [["id": "acme.view", "name": "Acme View"]]],
            ],
        ]
        for (key, value) in overrides { dict[key] = value }
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    func testValidManifestParses() throws {
        let manifest = try VSCodeManifestParser.parse(data: packageJSON())
        XCTAssertEqual(manifest.identity.id, "acme.sample")
        XCTAssertEqual(manifest.metadata.displayName, "Sample")
        XCTAssertEqual(manifest.enginesVscode, "^1.80.0")
        XCTAssertEqual(manifest.allDependencies, ["other.dep"])
        XCTAssertEqual(manifest.contributesCommands.count, 1)
        XCTAssertEqual(manifest.contributesViews.count, 1)
        XCTAssertEqual(manifest.declaredAPIs, ["commands", "TreeDataProvider"])
    }

    func testMissingNameIsRejected() {
        XCTAssertThrowsError(try VSCodeManifestParser.parse(data: packageJSON(["name": ""])))
    }

    func testMissingPublisherIsRejected() {
        XCTAssertThrowsError(try VSCodeManifestParser.parse(data: packageJSON(["publisher": ""])))
    }

    func testUnparseableVersionIsRejected() {
        XCTAssertThrowsError(try VSCodeManifestParser.parse(data: packageJSON(["version": "banana"])))
    }

    func testUnsafeMainIsRejected() {
        XCTAssertThrowsError(try VSCodeManifestParser.parse(data: packageJSON(["main": "../evil.js"])))
        XCTAssertThrowsError(try VSCodeManifestParser.parse(data: packageJSON(["main": "/abs/path.js"])))
        XCTAssertTrue(VSCodeManifestParser.isUnsafeRelativePath("../x"))
        XCTAssertFalse(VSCodeManifestParser.isUnsafeRelativePath("./dist/index.js"))
    }

    func testIdentitySplitsOnFirstDot() {
        XCTAssertEqual(ExtensionIdentity(id: "a.b.c")?.publisher, "a")
        XCTAssertEqual(ExtensionIdentity(id: "a.b.c")?.name, "b.c")
        XCTAssertNil(ExtensionIdentity(id: ".name"))
        XCTAssertNil(ExtensionIdentity(id: "publisher."))
        XCTAssertNil(ExtensionIdentity(id: "nodot"))
    }

    // MARK: Versions

    func testVersionParsing() {
        XCTAssertEqual(SemanticVersion(string: "1.80"), SemanticVersion(major: 1, minor: 80, patch: 0))
        XCTAssertEqual(SemanticVersion(string: "1.80.x"), SemanticVersion(major: 1, minor: 80, patch: 0))
        XCTAssertEqual(SemanticVersion(string: "v2.0.1-beta.1"), SemanticVersion(major: 2, minor: 0, patch: 1))
        XCTAssertEqual(SemanticVersion(string: " 1.2.3 "), SemanticVersion(major: 1, minor: 2, patch: 3))
        XCTAssertNil(SemanticVersion(string: "banana"))
        XCTAssertNil(SemanticVersion(string: ""))
        XCTAssertTrue(SemanticVersion(major: 1, minor: 85, patch: 0) > SemanticVersion(major: 1, minor: 80, patch: 9))
    }

    func testVersionSatisfiesEngineRequirements() {
        let host = SemanticVersion(major: 1, minor: 85, patch: 0)
        XCTAssertTrue(host.satisfies(engineRequirement: "*"))
        XCTAssertTrue(host.satisfies(engineRequirement: "x"))
        XCTAssertTrue(host.satisfies(engineRequirement: ""))
        XCTAssertTrue(host.satisfies(engineRequirement: ">=1.80.0"))
        XCTAssertFalse(host.satisfies(engineRequirement: ">=1.90.0"))
        XCTAssertTrue(host.satisfies(engineRequirement: "^1.80.0"))
        XCTAssertFalse(host.satisfies(engineRequirement: "^2.0.0"))
        XCTAssertTrue(host.satisfies(engineRequirement: "1.85.x"))
        XCTAssertFalse(host.satisfies(engineRequirement: "1.84.x"))
        XCTAssertTrue(host.satisfies(engineRequirement: "1.85.0"))
        XCTAssertFalse(host.satisfies(engineRequirement: "1.85.1"))
        XCTAssertFalse(host.satisfies(engineRequirement: "not-a-version"))
    }

    // MARK: Compatibility

    func testCompatibilityHappyPath() throws {
        let manifest = try VSCodeManifestParser.parse(data: packageJSON())
        let report = Compatibility.evaluate(manifest: manifest)
        XCTAssertTrue(report.compatible)
        XCTAssertTrue(report.reasons.isEmpty)
    }

    func testCompatibilityMissingEngineIsIncompatible() throws {
        var dict = try JSONSerialization.jsonObject(with: packageJSON()) as! [String: Any]
        dict.removeValue(forKey: "engines")
        let manifest = try VSCodeManifestParser.parse(
            data: try JSONSerialization.data(withJSONObject: dict))
        let report = Compatibility.evaluate(manifest: manifest)
        XCTAssertFalse(report.compatible)
        XCTAssertTrue(report.reasons.contains { $0.contains("no engines.vscode requirement") })
    }

    func testCompatibilityEngineTooNewIsIncompatible() throws {
        let manifest = try VSCodeManifestParser.parse(data: packageJSON(["engines": ["vscode": "^9.0.0"]]))
        XCTAssertFalse(Compatibility.evaluate(manifest: manifest).compatible)
    }

    func testCompatibilityCommandsWithoutEntryPointAreIncompatible() throws {
        var dict = try JSONSerialization.jsonObject(with: packageJSON()) as! [String: Any]
        dict.removeValue(forKey: "main")
        let manifest = try VSCodeManifestParser.parse(
            data: try JSONSerialization.data(withJSONObject: dict))
        XCTAssertFalse(Compatibility.evaluate(manifest: manifest).compatible)
    }

    func testCompatibilityPurelyDeclarativeManifestCanBeCompatible() throws {
        let data = packageJSON(["main": NSNull(), "contributes": ["grammars": [["language": "foo"]]] as [String: Any]])
        // No commands/views, no main: no reason from rule 3; engine requirement satisfied.
        let manifest = try VSCodeManifestParser.parse(data: data)
        XCTAssertTrue(Compatibility.evaluate(manifest: manifest).compatible)
    }

    // MARK: Strict swiftcode.json validator

    private func swiftcodeJSON(_ overrides: [String: Any] = [:]) -> Data {
        var dict: [String: Any] = [
            "manifestVersion": 1,
            "id": "com.example.my-extension",
            "name": "My Extension",
            "version": "0.1.0",
            "description": "Plain-language description.",
            "type": "extension",
            "runtime": ["language": "typescript", "entrypoint": "dist/index.js",
                        "minimumSwiftCodeVersion": "1.0.0"],
            "sdk": ["name": "@swiftcode/sdk", "versionRange": "^1.0.0", "protocolVersion": 1],
            "capabilities": [["id": "workspace.read", "reason": "Read workspace files."]],
            "contributes": ["commands": [["id": "run-build", "title": "Build Current Project"]]],
            "assist": ["requested": false],
        ]
        for (key, value) in overrides { dict[key] = value }
        return try! JSONSerialization.data(withJSONObject: dict)
    }

    func testStrictValidatorAcceptsCanonicalManifest() throws {
        let manifest = try SwiftCodeManifestValidator.validate(data: swiftcodeJSON())
        XCTAssertEqual(manifest.id, "com.example.my-extension")
        XCTAssertEqual(manifest.capabilities.count, 1)
        XCTAssertEqual(manifest.assist.requested, false)
    }

    func testStrictValidatorRejectsUppercaseID() {
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["id": "com.Example.Bad"])))
    }

    func testStrictValidatorRejectsTwoPartVersion() {
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["version": "1.0"])))
    }

    func testStrictValidatorAllowsPrereleaseVersion() throws {
        let manifest = try SwiftCodeManifestValidator.validate(data: swiftcodeJSON(["version": "1.0.0-beta.1"]))
        XCTAssertEqual(manifest.version, "1.0.0-beta.1")
    }

    func testStrictValidatorRejectsBadSDKRange() {
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["sdk": ["name": "@swiftcode/sdk", "versionRange": "^2.0.0", "protocolVersion": 1]])))
    }

    func testStrictValidatorRejectsUnknownCapability() {
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["capabilities": [["id": "not.a.capability", "reason": "Because."]]])))
    }

    func testStrictValidatorRejectsDuplicateCapabilities() {
        let caps: [[String: String]] = [
            ["id": "workspace.read", "reason": "Read workspace files."],
            ["id": "workspace.read", "reason": "Read workspace files again."],
        ]
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["capabilities": caps])))
    }

    func testStrictValidatorRejectsBlankCapabilityReason() {
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["capabilities": [["id": "workspace.read", "reason": "  "]]])))
    }

    func testStrictValidatorRejectsBadCommandID() {
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["contributes": ["commands": [["id": "Run_Build", "title": "Build"]]]])))
    }

    func testStrictValidatorReportsMissingKeysWithDiagnostics() {
        var dict = try! JSONSerialization.jsonObject(with: swiftcodeJSON()) as! [String: Any]
        dict.removeValue(forKey: "id")
        dict.removeValue(forKey: "capabilities")
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let diagnostics = SwiftCodeManifestValidator.validateWithDiagnostics(data: data)
        XCTAssertTrue(diagnostics.contains { $0.severity == .error && $0.field == "id" })
        XCTAssertTrue(diagnostics.contains { $0.severity == .error && $0.field == "capabilities" })
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(data: data))
    }

    func testStrictValidatorRejectsOversizeManifest() {
        let big = Data(repeating: UInt8(ascii: " "), count: 64 * 1024 + 1)
        XCTAssertThrowsError(try SwiftCodeManifestValidator.validate(data: big))
    }

    func testSDKRangeWhitelist() {
        XCTAssertTrue(SwiftCodeManifestValidator.isSDKRangeCompatible("1.2.0"))
        XCTAssertTrue(SwiftCodeManifestValidator.isSDKRangeCompatible("^1.0.0"))
        XCTAssertTrue(SwiftCodeManifestValidator.isSDKRangeCompatible("~1.1.0"))
        XCTAssertTrue(SwiftCodeManifestValidator.isSDKRangeCompatible(">=1.0.0 <2.0.0"))
        XCTAssertFalse(SwiftCodeManifestValidator.isSDKRangeCompatible("^2.0.0"))
        XCTAssertFalse(SwiftCodeManifestValidator.isSDKRangeCompatible("1.3.0"))
        XCTAssertFalse(SwiftCodeManifestValidator.isSDKRangeCompatible("banana"))
        XCTAssertEqual(SwiftCodeManifestValidator.supportedCapabilities.count, 41)
    }

    func testUnknownFieldsArePreserved() throws {
        let manifest = try SwiftCodeManifestValidator.validate(
            data: swiftcodeJSON(["customField": "keep-me"]))
        XCTAssertEqual(manifest.unknownFields["customField"], .string("keep-me"))
        let reencoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SwiftCodeManifest.self, from: reencoded)
        XCTAssertEqual(decoded.unknownFields["customField"], .string("keep-me"))
    }
}
