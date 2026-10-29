import Foundation

// MARK: - Extensions v2 in-app test suite
//
// Follows the repo's AssistRuntimeTestSuite convention: tests run
// inside the app and return RuntimeTestCaseResult values, instead of
// XCTest (which the app target does not link). Every case here is
// offline and deterministic — no registry, no host process, no Node.
// The suite is runnable from Extensions > Diagnostics ("Run
// self-tests"). Registry download, package extraction, and host
// activation are integration paths verified on Dylan's Mac (see
// Docs/Extensions-v2.md checklist); they are not faked here.

@MainActor
public final class ExtV2TestSuite: Sendable {
    public static let shared = ExtV2TestSuite()

    private init() {}

    public func runAllTests() async -> RuntimeTestSuiteReport {
        let start = Date()
        var results: [RuntimeTestCaseResult] = []
        results.append(await check("Version parsing and comparison") {
            guard ExtV2Version(string: "1.85.0") == ExtV2Version(major: 1, minor: 85, patch: 0) else {
                throw ExtV2Error.unknown("Version did not parse to 1.85.0")
            }
            guard ExtV2Version(string: "not-a-version") == nil else {
                throw ExtV2Error.unknown("Invalid version parsed successfully")
            }
            guard ExtV2Version(string: "1.85.1")! > ExtV2Version(string: "1.85.0")! else {
                throw ExtV2Error.unknown("Version comparison failed")
            }
        })
        results.append(await check("Engine requirement forms") {
            let host = ExtV2Version(major: 1, minor: 85, patch: 0)
            let cases: [(String, Bool)] = [
                ("^1.80.0", true), (">=1.80.0", true), ("*", true),
                ("1.85.x", true), ("^1.86.0", false), (">=1.86.0", false),
                ("garbage", false),
            ]
            for (requirement, expected) in cases {
                guard host.satisfies(engineRequirement: requirement) == expected else {
                    throw ExtV2Error.unknown("Requirement '\(requirement)' evaluated wrongly")
                }
            }
        })
        results.append(await check("Manifest parses") {
            let manifest = try ExtV2TestSuite.manifest()
            guard manifest.identity.id == "acme.demo", manifest.enginesVscode == "^1.80.0" else {
                throw ExtV2Error.unknown("Manifest fields mismatch")
            }
        })
        results.append(await check("Manifest rejects missing publisher and escaping main") {
            var dict = try JSONSerialization.jsonObject(with: ExtV2TestSuite.manifestData()) as! [String: Any]
            dict.removeValue(forKey: "publisher")
            let missingPublisher = try JSONSerialization.data(withJSONObject: dict)
            guard (try? ExtV2ManifestParser.parse(data: missingPublisher)) == nil else {
                throw ExtV2Error.unknown("Manifest without publisher parsed")
            }
            guard (try? ExtV2ManifestParser.parse(data: ExtV2TestSuite.manifestData(main: "../evil.js"))) == nil,
                  (try? ExtV2ManifestParser.parse(data: ExtV2TestSuite.manifestData(main: "/abs/evil.js"))) == nil else {
                throw ExtV2Error.unknown("Manifest with escaping main parsed")
            }
        })
        results.append(await check("Compatibility rejects newer engine and missing engine") {
            let newer = try ExtV2ManifestParser.parse(data: ExtV2TestSuite.manifestData(engine: "^1.99.0"))
            guard !ExtV2Compatibility.evaluate(manifest: newer).compatible else {
                throw ExtV2Error.unknown("Newer engine reported compatible")
            }
            let noEngine = try ExtV2ManifestParser.parse(data: ExtV2TestSuite.manifestData(engine: nil))
            guard !ExtV2Compatibility.evaluate(manifest: noEngine).compatible else {
                throw ExtV2Error.unknown("Missing engine reported compatible")
            }
        })
        results.append(await check("Dependency resolution finds missing and cycles") {
            let manifest = try ExtV2ManifestParser.parse(data: ExtV2TestSuite.manifestData(dependencies: ["other.thing"]))
            let missing = ExtV2DependencyResolver.resolve(
                requested: [manifest], installedIDs: [], manifestsByID: [manifest.identity.id: manifest])
            guard missing.missing == ["other.thing"], !missing.isSatisfied else {
                throw ExtV2Error.unknown("Missing dependency not reported")
            }
            let a = try ExtV2ManifestParser.parse(data: ExtV2TestSuite.manifestData(name: "a", dependencies: ["acme.b"]))
            let b = try ExtV2ManifestParser.parse(data: ExtV2TestSuite.manifestData(name: "b", dependencies: ["acme.a"]))
            let cyclic = ExtV2DependencyResolver.resolve(
                requested: [a], installedIDs: [], manifestsByID: ["acme.a": a, "acme.b": b])
            guard !cyclic.cycles.isEmpty, !cyclic.isSatisfied else {
                throw ExtV2Error.unknown("Dependency cycle not detected")
            }
        })
        results.append(await check("Editor edits apply, handle emoji, reject overlaps") {
            let updated = try ExtV2EditorBridge.applyEdits([
                ExtV2TextEdit(
                    range: ExtV2TextRange(start: ExtV2TextPosition(line: 1, character: 0), end: ExtV2TextPosition(line: 1, character: 5)),
                    newText: "goodbye")
            ], to: "hello\nworld\n!")
            guard updated == "hello\ngoodbye\n!" else {
                throw ExtV2Error.unknown("Editor edit produced '\(updated)'")
            }
            let emoji = try ExtV2EditorBridge.applyEdits([
                ExtV2TextEdit(
                    range: ExtV2TextRange(start: ExtV2TextPosition(line: 0, character: 1), end: ExtV2TextPosition(line: 0, character: 2)),
                    newText: "b")
            ], to: "🎉a")
            guard emoji == "🎉b" else {
                throw ExtV2Error.unknown("Emoji edit produced '\(emoji)'")
            }
            let overlapping = [
                ExtV2TextEdit(range: ExtV2TextRange(start: ExtV2TextPosition(line: 0, character: 0), end: ExtV2TextPosition(line: 0, character: 3)), newText: "x"),
                ExtV2TextEdit(range: ExtV2TextRange(start: ExtV2TextPosition(line: 0, character: 2), end: ExtV2TextPosition(line: 0, character: 5)), newText: "y"),
            ]
            guard (try? ExtV2EditorBridge.applyEdits(overlapping, to: "hello")) == nil else {
                throw ExtV2Error.unknown("Overlapping edits were accepted")
            }
            guard ExtV2EditorBridge.offset(for: ExtV2TextPosition(line: 1, character: 2), in: "ab\ncdef") == 5 else {
                throw ExtV2Error.unknown("Editor offset wrong")
            }
        })
        results.append(await check("Xcode sort-lines command and buffer safety") {
            let buffer = ExtV2SourceTextBuffer(
                text: "banana\nApple\ncherry",
                selections: [ExtV2SourceRange(
                    start: ExtV2SourcePosition(line: 0, column: 0),
                    end: ExtV2SourcePosition(line: 2, column: 6))])
            let registry = ExtV2XcodeCommandRegistry()
            registry.register(ExtV2SortLinesCommand())
            try await registry.perform(identifier: "com.swiftcode.xcode.sortLines", buffer: buffer)
            guard buffer.completeBuffer == "Apple\nbanana\ncherry" else {
                throw ExtV2Error.unknown("Sort produced '\(buffer.completeBuffer)'")
            }
            let guarded = ExtV2SourceTextBuffer(text: "hello")
            let overlapping = [
                ExtV2SourceTextBuffer.Edit(range: ExtV2SourceRange(start: ExtV2SourcePosition(line: 0, column: 0), end: ExtV2SourcePosition(line: 0, column: 3)), newText: "x"),
                ExtV2SourceTextBuffer.Edit(range: ExtV2SourceRange(start: ExtV2SourcePosition(line: 0, column: 2), end: ExtV2SourcePosition(line: 0, column: 5)), newText: "y"),
            ]
            guard (try? guarded.applyEdits(overlapping)) == nil, guarded.completeBuffer == "hello" else {
                throw ExtV2Error.unknown("Failed Xcode batch mutated the buffer")
            }
        })
        results.append(await check("RPC round-trip, disallowed methods, oversize messages") {
            let request = ExtV2RPCRequest(id: "test-1", method: "host.log", params: .string("hello"))
            let data = try ExtV2RPC.encodeRequest(request)
            guard data.last == 0x0A else { throw ExtV2Error.unknown("NDJSON terminator missing") }
            let decoded = try ExtV2RPC.decodeRequest(from: Data(data.dropLast()), fromHost: true)
            guard decoded.id == "test-1" else { throw ExtV2Error.unknown("RPC round-trip id mismatch") }
            let bad = ExtV2RPCRequest(id: "test-2", method: "host.deleteEverything", params: nil)
            let badData = try ExtV2RPC.encodeRequest(bad)
            guard (try? ExtV2RPC.decodeRequest(from: Data(badData.dropLast()), fromHost: true)) == nil else {
                throw ExtV2Error.unknown("Disallowed IPC method was accepted")
            }
            let oversize = Data(repeating: 0x61, count: ExtV2ResourceLimits.maxIPCMessageBytes + 1)
            guard (try? ExtV2RPC.decodeRequest(from: oversize, fromHost: true)) == nil else {
                throw ExtV2Error.unknown("Oversize IPC message was accepted")
            }
            let value: ExtV2JSONValue = .object(["a": .int(1), "b": .array([.string("x"), .bool(true), .null])])
            let encoded = try JSONEncoder().encode(value)
            guard try JSONDecoder().decode(ExtV2JSONValue.self, from: encoded) == value else {
                throw ExtV2Error.unknown("JSON value round-trip failed")
            }
        })
        results.append(await check("Permissions deny by default, grant, revoke") {
            let manager = ExtV2PermissionManager(grants: [:])
            guard !manager.isGranted(extensionId: "acme.demo", capability: .workspaceWrite),
                  (try? manager.check(extensionId: "acme.demo", capability: .workspaceWrite)) == nil else {
                throw ExtV2Error.unknown("Permission was granted by default")
            }
            manager.grant(extensionId: "acme.demo", capability: .workspaceWrite)
            guard manager.isGranted(extensionId: "acme.demo", capability: .workspaceWrite) else {
                throw ExtV2Error.unknown("Grant did not take effect")
            }
            manager.revoke(extensionId: "acme.demo", capability: .workspaceWrite)
            guard !manager.isGranted(extensionId: "acme.demo", capability: .workspaceWrite) else {
                throw ExtV2Error.unknown("Revoke did not take effect")
            }
            let approved = await manager.request(extensionId: "acme.demo", capability: .network, reason: "test")
            guard !approved else {
                throw ExtV2Error.unknown("Permission request without a handler was approved")
            }
        })
        results.append(await check("Identity parsing and Assist descriptor validation") {
            guard ExtV2Identity(id: "acme.demo")?.publisher == "acme",
                  ExtV2Identity(id: "nodot") == nil,
                  ExtV2Identity(id: ".demo") == nil else {
                throw ExtV2Error.unknown("Identity parsing wrong")
            }
            let descriptor = ExtV2AssistCapability(
                toolId: "extv2.acme.demo.cmd", name: "Demo", description: "d",
                parameters: ["path": "string"], requiredParameters: ["path"],
                extensionId: "acme.demo", command: "demo.cmd")
            guard (try? descriptor.validate(input: [:])) == nil,
                  (try? descriptor.validate(input: ["path": 42])) == nil,
                  (try? descriptor.validate(input: ["path": "/tmp/x"])) != nil else {
                throw ExtV2Error.unknown("Assist descriptor validation wrong")
            }
            guard ExtV2AssistBridge.toolId(for: "acme.demo", command: "demo.cmd") == "extv2.acme.demo.demo.cmd" else {
                throw ExtV2Error.unknown("Assist tool id wrong")
            }
        })
        results.append(await check("use_extension validation") {
            guard UseExtensionAction(rawValue: "bogus") == nil else {
                throw ExtV2Error.unknown("Unknown action parsed successfully")
            }
            guard (try? UseExtensionRouter.validate(action: .details, extensionId: nil, command: nil, file: nil, confirm: false)) == nil else {
                throw ExtV2Error.unknown("details without extensionId validated")
            }
            guard (try? UseExtensionRouter.validate(action: .execute, extensionId: "acme.demo", command: "demo.cmd", file: nil, confirm: false)) == nil else {
                throw ExtV2Error.unknown("execute without confirm validated")
            }
            try UseExtensionRouter.validate(action: .list, extensionId: nil, command: nil, file: nil, confirm: false)
            try UseExtensionRouter.validate(
                action: .runXcodeCommand, extensionId: nil, command: "com.swiftcode.xcode.sortLines",
                file: "demo.txt", confirm: true)
            guard UseExtensionRouter.clampedLimit(999) == 200, UseExtensionRouter.clampedLimit(nil) == 50 else {
                throw ExtV2Error.unknown("Limit clamping wrong")
            }
        })
        results.append(await check("use_extension Xcode file round-trip") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtV2UseExtensionTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let fileURL = root.appendingPathComponent("demo.txt")
            try "banana\nApple\ncherry".write(to: fileURL, atomically: true, encoding: .utf8)
            ExtV2XcodeCommandRegistry.shared.register(ExtV2SortLinesCommand())
            let outcome = try await UseExtensionRouter.run(
                action: .runXcodeCommand, extensionId: nil, command: "com.swiftcode.xcode.sortLines",
                file: "demo.txt", selection: nil, args: [:], limit: 50, workspaceRoot: root)
            guard outcome.filesChanged == ["demo.txt"] else {
                throw ExtV2Error.unknown("Xcode round-trip did not report the changed file")
            }
            let updated = try String(contentsOf: fileURL, encoding: .utf8)
            guard updated == "Apple\nbanana\ncherry" else {
                throw ExtV2Error.unknown("Xcode round-trip produced '\(updated)'")
            }
        })
        results.append(await check("use_extension Xcode failures are honest") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ExtV2UseExtensionTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let fileURL = root.appendingPathComponent("demo.txt")
            try "banana\nApple".write(to: fileURL, atomically: true, encoding: .utf8)
            let unknown = try? await UseExtensionRouter.run(
                action: .runXcodeCommand, extensionId: nil, command: "com.example.nope",
                file: "demo.txt", selection: nil, args: [:], limit: 50, workspaceRoot: root)
            guard unknown == nil else {
                throw ExtV2Error.unknown("Unknown Xcode command succeeded")
            }
            let escaped = try? await UseExtensionRouter.run(
                action: .runXcodeCommand, extensionId: nil, command: "com.swiftcode.xcode.sortLines",
                file: "../escape.txt", selection: nil, args: [:], limit: 50, workspaceRoot: root)
            guard escaped == nil else {
                throw ExtV2Error.unknown("Workspace-escaping file was accepted")
            }
            let unchanged = try String(contentsOf: fileURL, encoding: .utf8)
            guard unchanged == "banana\nApple" else {
                throw ExtV2Error.unknown("Failed Xcode runs mutated the file")
            }
        })
        let passed = results.filter { $0.passed }.count
        return RuntimeTestSuiteReport(
            totalTests: results.count, passedTests: passed,
            failedTests: results.count - passed, results: results,
            totalDuration: Date().timeIntervalSince(start))
    }

    private func check(_ name: String, _ body: () async throws -> Void) async -> RuntimeTestCaseResult {
        let start = Date()
        do {
            try await body()
            return RuntimeTestCaseResult(testName: name, passed: true, message: "Passed", duration: Date().timeIntervalSince(start))
        } catch {
            return RuntimeTestCaseResult(testName: name, passed: false, message: error.localizedDescription, duration: Date().timeIntervalSince(start))
        }
    }

    // MARK: Fixtures

    private static func manifest() throws -> ExtV2VSCodeManifest {
        try ExtV2ManifestParser.parse(data: manifestData())
    }

    private static func manifestData(
        name: String = "demo", engine: String? = "^1.80.0",
        main: String? = "./out/extension.js", dependencies: [String] = []
    ) -> Data {
        var dict: [String: Any] = [
            "name": name, "publisher": "acme", "version": "1.0.0",
            "displayName": "Demo", "description": "A demo extension",
            "activationEvents": ["onStartupFinished"], "categories": ["Other"],
        ]
        if let engine { dict["engines"] = ["vscode": engine] }
        if let main { dict["main"] = main }
        if !dependencies.isEmpty { dict["extensionDependencies"] = dependencies }
        return try! JSONSerialization.data(withJSONObject: dict)
    }
}
