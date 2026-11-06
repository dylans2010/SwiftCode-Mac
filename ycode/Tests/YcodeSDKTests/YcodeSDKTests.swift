import Foundation
import XCTest
@testable import YcodeSDK

// MARK: - Wave 14 slice: SDK Contracts + Sources kits
//
// XCTest (the repo convention), no live network, no real credentials.
// Filesystem tests use throwaway directories under NSTemporaryDirectory,
// plus the checked-in example-manifest fixture and the Ycode repo itself
// (derived from #file, for the live-git tests).

final class YcodeSDKTests: XCTestCase {

    // MARK: Helpers

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/repository-build-extension.swiftcode.json")
    }

    /// The Ycode repo root, derived from this file's location
    /// (…/ycode/Tests/YcodeSDKTests → …/ycode → repo root).
    private var repoRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func tempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("YcodeSDKTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - SDKError

    func testSDKErrorTitlesAndCorrelationId() {
        let err = SDKError(code: .buildFailed, message: "boom")
        XCTAssertTrue(err.correlationId.hasPrefix("ERR-"))
        XCTAssertEqual(err.code.userFacingTitle, "Build failed")
        XCTAssertTrue(err.userFacingDescription.contains("[\(err.correlationId)]"))
        XCTAssertEqual(SDKErrorCode.allCases.count, 42)
        XCTAssertEqual(SDKErrorCode.cloudModelDenied.rawValue, "CLOUD_MODEL_DENIED")
    }

    func testSDKErrorCodableRoundTrip() throws {
        let err = SDKError(code: .manifestInvalid, message: "bad", suggestion: "fix it",
                           diagnostics: ["field": "id"])
        let data = try JSONEncoder().encode(err)
        let decoded = try JSONDecoder().decode(SDKError.self, from: data)
        XCTAssertEqual(decoded.code, .manifestInvalid)
        XCTAssertEqual(decoded.message, "bad")
        XCTAssertEqual(decoded.suggestion, "fix it")
        XCTAssertEqual(decoded.diagnostics?["field"], "id")
    }

    // MARK: - IPC envelopes

    func testIPCRequestResponseRoundTrip() throws {
        struct Ping: Codable, Sendable { let message: String }
        let request = SDKRequestEnvelope(requestId: "r-1", method: "sourceControl.getStatus",
                                         payload: Ping(message: "hi"))
        let data = SDKIPCCodec.encodeRequest(request)
        XCTAssertFalse(data.contains(UInt8(ascii: "\n")))
        let decoded = try JSONDecoder().decode(SDKRequestEnvelope<Ping>.self, from: data)
        XCTAssertEqual(decoded.protocolVersion, 1)
        XCTAssertEqual(decoded.type, .request)
        XCTAssertEqual(decoded.method, "sourceControl.getStatus")
        XCTAssertEqual(decoded.payload.message, "hi")

        let response = SDKResponseEnvelope(requestId: "r-1", payload: Ping(message: "pong"))
        let responseData = SDKIPCCodec.encodeResponse(response)
        let decodedResponse = try JSONDecoder().decode(SDKResponseEnvelope<Ping>.self, from: responseData)
        XCTAssertTrue(decodedResponse.ok)
        XCTAssertEqual(decodedResponse.payload?.message, "pong")
        XCTAssertNil(decodedResponse.error)

        let errorResponse = SDKResponseEnvelope<Ping>(
            requestId: "r-1",
            error: SDKErrorPayload(from: SDKError(code: .permissionDenied, message: "nope"))
        )
        let errorData = SDKIPCCodec.encodeResponse(errorResponse)
        let decodedError = try JSONDecoder().decode(SDKResponseEnvelope<Ping>.self, from: errorData)
        XCTAssertFalse(decodedError.ok)
        XCTAssertEqual(decodedError.error?.code, "PERMISSION_DENIED")
        XCTAssertNil(decodedError.payload)

        let event = SDKEventEnvelope(requestId: "r-1", event: "build.output",
                                     payload: Ping(message: "line"))
        let eventData = SDKIPCCodec.encodeEvent(event)
        let decodedEvent = try JSONDecoder().decode(SDKEventEnvelope<Ping>.self, from: eventData)
        XCTAssertEqual(decodedEvent.type, .event)
        XCTAssertEqual(decodedEvent.event, "build.output")
    }

    func testIPCDecodeRejectsOversizeAndMalformed() {
        XCTAssertThrowsError(try SDKIPCCodec.decodeEnvelopeType(from: Data(repeating: 0x20, count: SDKIPCCodec.maxMessageBytes + 1))) { error in
            XCTAssertEqual((error as? SDKError)?.code, .resourceLimitExceeded)
        }
        XCTAssertThrowsError(try SDKIPCCodec.decodeEnvelopeType(from: Data("not json".utf8))) { error in
            XCTAssertEqual((error as? SDKError)?.code, .ipcMalformed)
        }
        let type = try! SDKIPCCodec.decodeEnvelopeType(
            from: Data(#"{"protocolVersion":1,"type":"event","requestId":"x"}"#.utf8))
        XCTAssertEqual(type, .event)
    }

    // MARK: - Version negotiation

    func testVersionNegotiation() throws {
        let host = SDKVersions(hostSDKVersion: "1.2.0", hostProtocolVersion: 1, hostApiVersion: "2026.1")
        XCTAssertNoThrow(try SDKCompatibility.check(manifestProtocolVersion: 1, sdkVersionRange: "^1.0.0", host: host))
        XCTAssertNoThrow(try SDKCompatibility.check(manifestProtocolVersion: 1, sdkVersionRange: "~1.2.0", host: host))
        XCTAssertNoThrow(try SDKCompatibility.check(manifestProtocolVersion: 1, sdkVersionRange: ">=1.0.0", host: host))
        XCTAssertNoThrow(try SDKCompatibility.check(manifestProtocolVersion: 1, sdkVersionRange: "1.2.0", host: host))
        XCTAssertThrowsError(try SDKCompatibility.check(manifestProtocolVersion: 2, sdkVersionRange: "^1.0.0", host: host)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .ipcProtocolMismatch)
        }
        XCTAssertThrowsError(try SDKCompatibility.check(manifestProtocolVersion: 1, sdkVersionRange: "^2.0.0", host: host)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .incompatibleSDKVersion)
        }
        XCTAssertThrowsError(try SDKCompatibility.check(manifestProtocolVersion: 1, sdkVersionRange: "banana", host: host)) { error in
            XCTAssertEqual((error as? SDKError)?.code, .manifestInvalid)
        }
        // Caret on 0.x pins the minor: ^0.2.3 does not admit host 0.3.0.
        let oldHost = SDKVersions(hostSDKVersion: "0.3.0", hostProtocolVersion: 1, hostApiVersion: "2026.1")
        XCTAssertThrowsError(try SDKCompatibility.check(manifestProtocolVersion: 1, sdkVersionRange: "^0.2.3", host: oldHost))
    }

    // MARK: - Contract decoding (tolerant shapes)

    func testDiffOptionsTolerantDecoding() throws {
        let empty = try JSONDecoder().decode(SDKDiffOptions.self, from: Data("{}".utf8))
        XCTAssertEqual(empty.maxBytes, 262_144)
        XCTAssertTrue(empty.includeUntracked)
        XCTAssertNil(empty.paths)
        let clamped = try JSONDecoder().decode(SDKDiffOptions.self, from: Data(#"{"maxBytes":0}"#.utf8))
        XCTAssertEqual(clamped.maxBytes, 1)
        let filtered = try JSONDecoder().decode(SDKDiffOptions.self, from: Data(#"{"paths":["Sources/A.swift"]}"#.utf8))
        XCTAssertEqual(filtered.paths, ["Sources/A.swift"])
    }

    func testSandboxRunRequestTolerantDecoding() throws {
        let minimal = try JSONDecoder().decode(SDKSandboxRunRequest.self, from: Data(#"{"command":"git"}"#.utf8))
        XCTAssertEqual(minimal.command, "git")
        XCTAssertTrue(minimal.args.isEmpty)
        XCTAssertNil(minimal.workingDirectory)
        XCTAssertNil(minimal.timeout)
        let full = try JSONDecoder().decode(SDKSandboxRunRequest.self, from: Data(#"{"command":"git","args":["status"],"workingDirectory":"/tmp","timeout":10}"#.utf8))
        XCTAssertEqual(full.args, ["status"])
        XCTAssertEqual(full.timeout, 10)
        // Present-but-wrongly-typed still fails.
        XCTAssertThrowsError(try JSONDecoder().decode(SDKSandboxRunRequest.self, from: Data(#"{"command":"git","args":"status"}"#.utf8)))
    }

    func testSecurityContractsCarryNoSecretBytes() throws {
        let add = SDKSecurityAddRequest(securityID: "api-keys", valueID: "github-token", label: "GitHub", prompt: "Paste your token")
        let data = try JSONEncoder().encode(add)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.lowercased().contains("secret"))
        XCTAssertFalse(text.lowercased().contains("token-value"))
        let use = SDKSecurityUseRequest(
            securityID: "api-keys", valueID: "github-token",
            operation: SDKSecurityUseOperation(kind: "httpAuthorization",
                                               request: SDKSecurityHTTPRequest(method: "GET", url: "https://api.github.com/user")))
        let useData = try JSONEncoder().encode(use)
        let decoded = try JSONDecoder().decode(SDKSecurityUseRequest.self, from: useData)
        XCTAssertEqual(decoded.operation.kind, "httpAuthorization")
        XCTAssertEqual(decoded.operation.request.url, "https://api.github.com/user")
    }

    func testCloudModelRequestRoundTrip() throws {
        let req = SDKCloudModelCompletionRequest(
            prompt: "hello",
            history: [SDKCloudModelHistoryEntry(role: "user", content: "hi")],
            modelIdentifier: "swiftcode-cloud-1")
        let decoded = try JSONDecoder().decode(SDKCloudModelCompletionRequest.self, from: JSONEncoder().encode(req))
        XCTAssertEqual(decoded.prompt, "hello")
        XCTAssertEqual(decoded.history.count, 1)
        XCTAssertEqual(decoded.modelIdentifier, "swiftcode-cloud-1")
    }

    func testBuildContractsRoundTrip() throws {
        let result = SDKBuildResult(status: .succeeded, exitCode: 0, durationSeconds: 1.5,
                                    diagnostics: [SDKBuildDiagnostic(file: "A.swift", line: 3, message: "warn")])
        let decoded = try JSONDecoder().decode(SDKBuildResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(decoded.status, .succeeded)
        XCTAssertEqual(decoded.diagnostics.first?.line, 3)
        let request = SDKBuildRequest(target: "App", configuration: "Debug", destination: "platform=macOS")
        let decodedRequest = try JSONDecoder().decode(SDKBuildRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decodedRequest.target, "App")
    }

    func testRepositoryStatusEmptyShape() {
        let status = SDKRepositoryStatus(isRepository: false)
        XCTAssertFalse(status.isRepository)
        XCTAssertNil(status.branchName)
        XCTAssertEqual(status.stagedCount, 0)
        XCTAssertTrue(status.files.isEmpty)
    }

    // MARK: - DiagnosticsKit

    func testDiagnosticEngine() {
        let engine = DiagnosticEngine()
        XCTAssertFalse(engine.hasErrors)
        engine.emit(code: .projectInvalidIdentifier, severity: .error, message: "bad id")
        engine.emit(code: .projectMissingTarget, severity: .warning, message: "no targets")
        XCTAssertTrue(engine.hasErrors)
        XCTAssertEqual(engine.errorCount, 1)
        XCTAssertEqual(engine.warningCount, 1)
        XCTAssertEqual(engine.allDiagnostics.count, 2)
        let text = DiagnosticFormatter.formatText(engine.allDiagnostics)
        XCTAssertTrue(text.contains("[SC-P004]"))
        XCTAssertTrue(text.contains("bad id"))
        XCTAssertEqual(DiagnosticFormatter.formatText([]), "No diagnostics reported.")
        XCTAssertTrue(DiagnosticSeverity.error > DiagnosticSeverity.warning)
        engine.clear()
        XCTAssertTrue(engine.allDiagnostics.isEmpty)
    }

    func testDiagnosticFormatterJSON() throws {
        let engine = DiagnosticEngine()
        engine.emit(code: .buildCompilerError, severity: .error, message: "type mismatch",
                    location: DiagnosticLocation(filePath: "A.swift", line: 10, column: 5))
        let json = try DiagnosticFormatter.formatJSON(engine.allDiagnostics)
        XCTAssertTrue(json.contains("type mismatch"))
        XCTAssertEqual(DiagnosticLocation(filePath: "A.swift", line: 10, column: 5).formattedDescription, "A.swift:10:5")
    }

    // MARK: - WorkspaceKit

    func testWorkspacePathTraversal() {
        let root = WorkspacePath("/tmp/project")
        XCTAssertTrue(WorkspacePath("/tmp/project/Sources/A.swift").isWithin(root: root))
        XCTAssertTrue(WorkspacePath("/tmp/project").isWithin(root: root))
        XCTAssertFalse(WorkspacePath("/tmp/other/A.swift").isWithin(root: root))
        XCTAssertFalse(WorkspacePath("/tmp/project/../etc/passwd").isWithin(root: root))
        XCTAssertEqual(WorkspacePath("/tmp/project").appending("Sources").normalizedPath, "/tmp/project/Sources")
    }

    func testSafeFileAccessReadWriteAndTraversal() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let access = SafeFileAccess(root: WorkspacePath(dir.path))
        try access.writeString("hello", to: "a/b.txt")
        XCTAssertEqual(try access.readString(at: "a/b.txt"), "hello")
        XCTAssertTrue(access.exists(at: "a/b.txt"))
        XCTAssertFalse(access.exists(at: "missing.txt"))
        XCTAssertThrowsError(try access.readFile(at: "../escape.txt"))
        XCTAssertThrowsError(try access.writeString("x", to: "../../escape.txt"))
        let files = try access.listFiles(recursively: true)
        XCTAssertTrue(files.contains { $0.relativePath == "a/b.txt" && !$0.isDirectory })
    }

    func testWorkspaceDiscoversProjects() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ws = Workspace(path: dir.path)
        try ws.fileAccess.writeString("// swift-tools-version: 6.0", to: "Package.swift")
        XCTAssertTrue(try ws.discoverProjects().contains { $0.hasSuffix("Package.swift") })
    }

    // MARK: - BuildKit parser

    func testBuildDiagnosticsParser() {
        let parser = BuildDiagnosticsParser()
        let output = """
        /Users/user/App/Sources/A.swift:10:5: error: cannot find 'foo' in scope
        /Users/user/App/Sources/B.swift:3:1: warning: unused variable 'x'
        src/index.ts(7,3): error TS2322: Type 'string' is not assignable.
        All good here.
        """
        let diags = parser.parse(output: output)
        XCTAssertEqual(diags.count, 3)
        XCTAssertEqual(diags[0].severity, .error)
        XCTAssertEqual(diags[0].location?.line, 10)
        XCTAssertEqual(diags[0].location?.column, 5)
        XCTAssertEqual(diags[1].severity, .warning)
        XCTAssertEqual(diags[2].code.rawValue, "SC-B005")
        XCTAssertEqual(diags[2].location?.filePath, "src/index.ts")
        XCTAssertTrue(parser.parse(output: "clean build").isEmpty)
    }

    // MARK: - ProjectKit

    func testProjectInspectorSwiftPackageAndExtension() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let inspector = ProjectInspector()
        // No recognised project → throws.
        XCTAssertThrowsError(try inspector.inspect(at: dir.path))
        // Swift package.
        try "let package = Package(name: \"Demo\")".write(
            to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let pkg = try inspector.inspect(at: dir.path)
        XCTAssertEqual(pkg.type, .swiftPackage)
        XCTAssertEqual(pkg.name, "Demo")
        // Extension manifest takes precedence over Package.swift.
        let fixture = try Data(contentsOf: fixtureURL)
        try fixture.write(to: dir.appendingPathComponent("swiftcode.json"))
        let ext = try inspector.inspect(at: dir.path)
        XCTAssertEqual(ext.type, .swiftcodeExtension)
        XCTAssertEqual(ext.id, "com.example.repository-build-extension")
        XCTAssertEqual(ext.customProperties["entrypoint"], "dist/index.js")
    }

    func testProjectValidator() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let validator = ProjectValidator()
        let bad = ProjectMetadata(id: "has space", name: "X", type: .swiftPackage,
                                  version: "1.0.0", rootPath: "/nonexistent-\(UUID().uuidString)")
        let diags = validator.validate(metadata: bad)
        XCTAssertTrue(diags.contains { $0.code == .projectInvalidIdentifier && $0.severity == .error })
        XCTAssertTrue(diags.contains { $0.code == .projectNotFound && $0.severity == .error })
        let ok = ProjectMetadata(id: "com.example.demo", name: "Demo", type: .swiftPackage,
                                 version: "1.0.0", rootPath: dir.path,
                                 targets: [ProjectTarget(name: "Demo")])
        XCTAssertTrue(validator.validate(metadata: ok).isEmpty)
        let noTargets = ProjectMetadata(id: "com.example.demo", name: "Demo", type: .swiftPackage,
                                        version: "1.0.0", rootPath: dir.path)
        XCTAssertTrue(validator.validate(metadata: noTargets).contains { $0.severity == .warning })
    }

    func testProjectGeneratorSwiftPackageRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("DemoPkg").path
        let meta = try ProjectGenerator().generate(options: ProjectGeneratorOptions(
            type: .swiftPackage, name: "DemoPkg", identifier: "com.example.demopkg",
            destinationDirectory: out))
        XCTAssertEqual(meta.type, .swiftPackage)
        XCTAssertEqual(meta.name, "DemoPkg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: (out as NSString).appendingPathComponent("Package.swift")))
        XCTAssertTrue(FileManager.default.fileExists(atPath: (out as NSString).appendingPathComponent("README.md")))
    }

    // MARK: - Manifest validator adapter + example fixture

    func testExampleManifestFixtureValidates() throws {
        let data = try Data(contentsOf: fixtureURL)
        let validator = SDKManifestValidator()
        let diags = validator.validate(data: data, packageRoot: fixtureURL.deletingLastPathComponent().path)
        XCTAssertFalse(diags.contains { $0.severity == .error }, DiagnosticFormatter.formatText(diags))
        let manifest = try validator.validateAndDecode(data: data)
        XCTAssertEqual(manifest.id, "com.example.repository-build-extension")
        XCTAssertEqual(manifest.sdk.protocolVersion, 1)
        XCTAssertEqual(manifest.capabilities.map { $0.id }, ["source-control.read", "build.execute"])
    }

    func testManifestValidatorRejectsInvalidJSON() {
        let validator = SDKManifestValidator()
        let diags = validator.validate(data: Data("{oops".utf8))
        XCTAssertTrue(diags.contains { $0.severity == .error })
        XCTAssertTrue(validator.validateFile(at: "/nonexistent-\(UUID().uuidString)").contains { $0.code == .manifestNotFound })
    }

    // MARK: - SourceControlKit (live git, repo derived from #file)

    func testSourceControlAgainstYcodeRepo() throws {
        let service = SourceControlService()
        let root = repoRootURL.path
        XCTAssertTrue(service.isGitRepository(at: root))
        let status = try service.getStatus(at: root)
        XCTAssertFalse(status.currentBranch.isEmpty)
        XCTAssertGreaterThanOrEqual(status.aheadCount, 0)
        XCTAssertGreaterThanOrEqual(status.behindCount, 0)
        let log = try service.getLog(at: root, limit: 2)
        XCTAssertFalse(log.isEmpty)
        XCTAssertFalse(log[0].hash.isEmpty)
        XCTAssertFalse(log[0].message.isEmpty)
    }

    func testSourceControlNotARepository() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = SourceControlService()
        XCTAssertFalse(service.isGitRepository(at: dir.path))
        XCTAssertThrowsError(try service.getStatus(at: dir.path)) { error in
            if case GitError.notARepository = error {} else { XCTFail("expected notARepository, got \(error)") }
        }
    }

    // MARK: - Toolchain / doctor (environment-dependent: assert shape, not availability)

    func testToolchainDiscoversKnownToolNames() {
        let tools = Toolchain.standard.discoverTools()
        for name in ["swift", "swiftc", "xcodebuild", "clang", "git", "node", "npm", "python3"] {
            XCTAssertNotNil(tools[name], "missing tool entry for \(name)")
            XCTAssertEqual(tools[name]?.name, name)
        }
    }

    func testDoctorReportShape() {
        let report = SDKDoctor().diagnose(sdkRoot: NSTemporaryDirectory())
        XCTAssertEqual(report.tools.count, 8)
        XCTAssertFalse(report.osVersion.isEmpty)
        XCTAssertFalse(report.architecture.isEmpty)
        XCTAssertTrue(report.sdkRootExists)
        XCTAssertEqual(report.isHealthy, !report.diagnostics.contains { $0.severity == .error })
    }

    func testSDKVersionAndConfiguration() {
        XCTAssertEqual(SDKVersion.current.description, "1.0.0")
        XCTAssertTrue(SDKVersion.current.isCompatibleWithHost)
        XCTAssertFalse(SDKVersion(major: 2, minor: 0, patch: 0).isCompatibleWithHost)
        let config = SDKConfiguration.standard(sdkRoot: "/tmp/sdk")
        XCTAssertEqual(config.binDirectory, "/tmp/sdk/bin")
        XCTAssertEqual(config.documentationDirectory, "/tmp/sdk/documentation")
    }

    // MARK: - CLI (no process exit: run returns codes)

    func testCLIHelpAndVersion() async {
        XCTAssertEqual(await SwiftCodeSDKCLI.run(arguments: ["--help"]), 0)
        XCTAssertEqual(await SwiftCodeSDKCLI.run(arguments: ["--version"]), 0)
        XCTAssertEqual(await SwiftCodeSDKCLI.run(arguments: ["nope"]), 1)
        XCTAssertEqual(await SwiftCodeSDKCLI.run(arguments: ["validate", "/nonexistent-\(UUID().uuidString)"]), 1)
    }

    func testCLIValidateFixture() async {
        XCTAssertEqual(await SwiftCodeSDKCLI.run(arguments: ["validate", fixtureURL.path]), 0)
    }

    func testToolMains() {
        XCTAssertEqual(ExtensionValidatorMain.run(arguments: [fixtureURL.path]), 0)
        XCTAssertEqual(ExtensionValidatorMain.run(arguments: ["/nonexistent-\(UUID().uuidString)"]), 1)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try! "# Guide\n".write(to: dir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(DocumentationIndexerMain.run(arguments: [dir.path]), 0)
        // The doctor's verdict is environment-dependent (swift may be
        // absent on a Linux workstation), so assert the tool's exit code
        // matches the doctor's own verdict rather than a fixed value.
        let healthy = SDKDoctor().diagnose(sdkRoot: NSTemporaryDirectory()).isHealthy
        XCTAssertEqual(DiagnosticsToolMain.run(arguments: [NSTemporaryDirectory()]), healthy ? 0 : 1)
    }
}
