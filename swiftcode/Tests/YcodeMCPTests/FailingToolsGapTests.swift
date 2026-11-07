import Foundation
import YcodeAssistant
import Testing
@testable import YcodeMCP

@MainActor
struct FailingToolsGapTests {
    func openHost(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        for tools in [host.terminalTools, host.agenticDataTools, host.agenticNetworkTools,
                      host.agenticExecutionTools, host.engineTools] {
            let names = Set(tools.map(\.name))
            host.server.tools = host.server.tools.filter { !names.contains($0.name) } + tools
        }
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func environmentBlockRedactsSecrets() {
        let (text, count) = SwiftCodeMCPHost.failingToolsEnvironmentBlock()
        #expect(count > 0)
        #expect(text.contains("PATH="))
        for line in text.components(separatedBy: .newlines) {
            let name = line.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            if SwiftCodeMCPHost.failingToolsIsSensitiveEnvName(name) {
                #expect(line.hasSuffix("=<redacted>"), Comment(rawValue: line))
            }
        }
        #expect(SwiftCodeMCPHost.failingToolsIsSensitiveEnvName("COMPOSIO_API_KEY"))
        #expect(SwiftCodeMCPHost.failingToolsIsSensitiveEnvName("MY_TOKEN"))
        #expect(!SwiftCodeMCPHost.failingToolsIsSensitiveEnvName("PATH"))
    }

    @Test func snapshotLineMatchesLegacyShape() {
        let entry = SwiftCodeMCPHost.FailingToolsSnapshotEntry(
            id: "abc", timestamp: Date(timeIntervalSince1970: 0), message: "hello")
        let line = SwiftCodeMCPHost.failingToolsSnapshotLine(entry)
        #expect(line.contains("hello") && line.contains("[abc]"))
    }

    @Test func envCaptureLogsReturnsRealEnvironment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("env_capture_logs")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect((r.structured?["environmentVariableCount"]?.int ?? 0) > 0)
        #expect(r.structured?["logs"]?.string != nil)
    }

    @Test func processLogsForUnknownPidFailsWithoutPlaceholder() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("get_process_logs", ["pid": .int(2_147_483_647)])
        #expect(r.isToolError)
        #expect(!r.resultText.contains("Log data for process"))
        #expect(r.resultText.contains("No process with PID"))
    }

    @Test func procFactsAreNilForUnknownPid() {
        #expect(SwiftCodeMCPHost.failingToolsProcFacts(pid: 2_147_483_647) == nil)
    }

    @Test func packageResolvedParsingCoversV1V2AndSkips() throws {
        let v2 = """
        { "pins": [
          { "identity": "swift-crypto", "location": "https://github.com/apple/swift-crypto.git",
            "state": { "version": "3.0.0" } },
          { "identity": "branchy", "location": "https://github.com/example/branchy.git",
            "state": { "branch": "main", "revision": "abc" } },
          { "identity": "local", "location": "/tmp/local",
            "state": { "revision": "abc" } }
        ] }
        """.data(using: .utf8)!
        let pkgs = try SwiftCodeMCPHost.dependencyAuditPackages(from: v2)
        #expect(pkgs.count == 3)
        #expect(pkgs[0].version == "3.0.0" && pkgs[0].skipReason == nil)
        #expect(pkgs[1].version == nil && (pkgs[1].skipReason ?? "").contains("branch"))
        #expect(pkgs[2].skipReason == "local path dependency")
        let v1 = """
        { "object": { "pins": [
          { "package": "swift-nio", "repositoryURL": "https://github.com/apple/swift-nio.git",
            "state": { "version": "2.0.0" } }
        ] } }
        """.data(using: .utf8)!
        let pkgs1 = try SwiftCodeMCPHost.dependencyAuditPackages(from: v1)
        #expect(pkgs1.count == 1 && pkgs1[0].name == "swift-nio" && pkgs1[0].version == "2.0.0")
    }

    @Test func osvQueryBodyUsesSwiftURL() throws {
        let pkgs = [SwiftCodeMCPHost.DependencyAuditPackage(name: "a", repositoryURL: "https://github.com/x/a.git", version: "1.0.0"),
                    SwiftCodeMCPHost.DependencyAuditPackage(name: "b", repositoryURL: "https://github.com/x/b.git", version: nil, skipReason: "no version")]
        let body = SwiftCodeMCPHost.dependencyAuditQueryBody(pkgs)
        let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let queries = obj?["queries"] as? [[String: Any]]
        #expect(queries?.count == 1)
        #expect((queries?[0]["package"] as? [String: Any])?["ecosystem"] as? String == "SwiftURL")
        #expect(queries?[0]["version"] as? String == "1.0.0")
    }

    @Test func osvBatchAndDetailParsing() throws {
        let batch = """
        { "results": [ { "vulns": [ { "id": "GHSA-xxxx-yyyy-zzzz", "summary": "Bad thing" } ] }, {} ] }
        """.data(using: .utf8)!
        let pkgs = [SwiftCodeMCPHost.DependencyAuditPackage(name: "a", repositoryURL: "https://github.com/x/a.git", version: "1.0.0"),
                    SwiftCodeMCPHost.DependencyAuditPackage(name: "b", repositoryURL: "https://github.com/x/b.git", version: "2.0.0")]
        let found = SwiftCodeMCPHost.dependencyAuditParseBatch(batch, packages: pkgs)
        #expect(found.count == 1 && found[0].id == "GHSA-xxxx-yyyy-zzzz" && found[0].package.name == "a")
        let detail = """
        { "id": "GHSA-xxxx-yyyy-zzzz", "summary": "Bad thing",
          "severity": [ { "type": "CVSS_V3", "score": "9.8" } ],
          "affected": [ { "ranges": [ { "events": [ { "introduced": "0" }, { "fixed": "1.0.1" } ] } ] } ],
          "references": [ { "url": "https://example.invalid/advisory" } ] }
        """.data(using: .utf8)!
        let vuln = SwiftCodeMCPHost.dependencyAuditParseDetail(detail, package: pkgs[0], id: "GHSA-xxxx-yyyy-zzzz", summary: "Bad thing")
        #expect(vuln.severity == "9.8" && vuln.fixedVersion == "1.0.1" && vuln.reference == "https://example.invalid/advisory")
    }

    @Test func dependencyAuditEndToEndWithStubbedOSV() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "Package.resolved", """
        { "pins": [ { "identity": "swift-crypto", "location": "https://github.com/apple/swift-crypto.git",
                      "state": { "version": "3.0.0" } } ] }
        """)
        SwiftCodeMCPHost.dependencyAuditTestFetcher = { body in
            if body.isEmpty {
                return """
                { "id": "GHSA-test-1", "summary": "Test advisory",
                  "severity": [ { "type": "CVSS_V3", "score": "7.5" } ],
                  "affected": [ { "ranges": [ { "events": [ { "introduced": "0" }, { "fixed": "3.0.1" } ] } ] } ],
                  "references": [ { "url": "https://example.invalid/a" } ] }
                """.data(using: .utf8)!
            }
            return """
            { "results": [ { "vulns": [ { "id": "GHSA-test-1", "summary": "Test advisory" } ] } ] }
            """.data(using: .utf8)!
        }
        defer { SwiftCodeMCPHost.dependencyAuditTestFetcher = nil }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("dependency_audit", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["vulnerableCount"]?.int == 1)
        #expect(r.structured?["auditedCount"]?.int == 1)
        #expect(r.resultText.contains("GHSA-test-1"))
    }

    @Test func dependencyAuditWithoutResolvedFailsHonestly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("dependency_audit", ["projectPath": .string(".")])
        #expect(r.isToolError && r.resultText.contains("No Package.resolved"))
    }

    @Test func mcpMessageParsing() {
        let ok = SwiftCodeMCPHost.externalMCPParseMessage(#"{"jsonrpc":"2.0","id":2,"result":{"tools":[]}}"#)
        #expect(ok != nil)
        if case .success(let value) = ok { #expect((value as? [String: Any])?["tools"] != nil) } else { Issue.record("expected success") }
        let err = SwiftCodeMCPHost.externalMCPParseMessage(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"nope"}}"#)
        if case .failure(let message) = err { #expect(message.message.contains("nope")) } else { Issue.record("expected failure") }
        #expect(SwiftCodeMCPHost.externalMCPParseMessage(#"{"jsonrpc":"2.0","method":"notifications/x"}"#) == nil)
    }

    @Test func mcpContentJoining() {
        let (text, isError) = SwiftCodeMCPHost.externalMCPJoinContent(
            ["content": [["type": "text", "text": "hello"], ["type": "text", "text": "world"]], "isError": false])
        #expect(text == "hello\nworld" && !isError)
        let (_, err) = SwiftCodeMCPHost.externalMCPJoinContent(["content": [["type": "text", "text": "boom"]], "isError": true])
        #expect(err)
    }

    @Test func mcpListServersWithTestConfig() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        SwiftCodeMCPHost.externalMCPTestConfig = [
            "demo": SwiftCodeMCPHost.ExternalMCPServer(name: "demo", command: "/bin/echo", args: [], env: [:], url: nil, headers: [:], transport: nil),
        ]
        defer { SwiftCodeMCPHost.externalMCPTestConfig = nil }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("use_mcp", ["serverName": .string("list"), "toolName": .string("list_servers"), "arguments": .string("{}")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("demo"))
        let unknown = try await host.server.callTool("use_mcp", ["serverName": .string("nope"), "toolName": .string("list_tools"), "arguments": .string("{}")])
        #expect(unknown.isToolError && unknown.resultText.contains("No MCP server named 'nope'"))
    }

    @Test func mcpStdioExchangeAgainstStubServer() async throws {
        guard let node = SwiftCodeMCPHost.reverseResolveNodeURL() else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-mcp-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("stub.mjs")
        try """
        import { createInterface } from "node:readline";
        const rl = createInterface({ input: process.stdin });
        rl.on("line", (line) => {
          const req = JSON.parse(line);
          if (req.method === "notifications/initialized") return;
          if (req.method === "initialize") {
            process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: req.id, result: { protocolVersion: "2025-03-26", capabilities: {}, serverInfo: { name: "stub", version: "1" } } }) + "\\n");
          } else if (req.method === "tools/list") {
            process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: req.id, result: { tools: [{ name: "echo", description: "Echoes" }] } }) + "\\n");
          } else if (req.method === "tools/call") {
            process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: req.id, result: { content: [{ type: "text", text: "echo:" + JSON.stringify(req.params.arguments) }] } }) + "\\n");
          }
        });
        """.write(to: script, atomically: true, encoding: .utf8)
        SwiftCodeMCPHost.externalMCPTestConfig = [
            "stub": SwiftCodeMCPHost.ExternalMCPServer(name: "stub", command: node.path, args: [script.path], env: [:], url: nil, headers: [:], transport: nil),
        ]
        defer { SwiftCodeMCPHost.externalMCPTestConfig = nil }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let list = try await host.server.callTool("use_mcp", ["serverName": .string("stub"), "toolName": .string("list_tools"), "arguments": .string("{}")])
        #expect(!list.isToolError, "\(list.resultText)")
        #expect(list.resultText.contains("echo"))
        let call = try await host.server.callTool("use_mcp", ["serverName": .string("stub"), "toolName": .string("echo"), "arguments": .string(#"{"msg":"hi"}"#)])
        #expect(!call.isToolError, "\(call.resultText)")
        #expect(call.resultText.contains("hi"))
    }

    @Test func composioSlugValidation() throws {
        #expect(try SwiftCodeMCPHost.composioValidateSlug("GITHUB_LIST_REPOS") == "GITHUB_LIST_REPOS")
        #expect(throws: MCPToolError.self) { _ = try SwiftCodeMCPHost.composioValidateSlug("") }
        #expect(throws: MCPToolError.self) { _ = try SwiftCodeMCPHost.composioValidateSlug("has space") }
        #expect(throws: MCPToolError.self) { _ = try SwiftCodeMCPHost.composioValidateSlug("a-b") }
        #expect(throws: MCPToolError.self) { _ = try SwiftCodeMCPHost.composioValidateSlug(String(repeating: "A", count: 129)) }
    }

    @Test func composioJSONObjectExtraction() {
        let obj = SwiftCodeMCPHost.composioExtractJSONObject("some log\n{\"successful\": true, \"logId\": \"abc\"}\nmore log")
        #expect(obj?["successful"] as? Bool == true)
        #expect(obj?["logId"] as? String == "abc")
        #expect(SwiftCodeMCPHost.composioExtractJSONObject("no json here") == nil)
    }

    @Test func composioWithoutKeyOrCLIFailsHonestly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("use_composio", ["toolSlug": .string("GITHUB_LIST_REPOS"), "arguments": .string("{}")])
        #expect(r.isToolError && r.resultText.contains("Composio service"))
    }

    @Test func workersValidationMatchesLegacy() throws {
        let long = String(repeating: "x", count: 600)
        let workers: [AnyJSON] = [
            .object(["name": .string("A"), "scope": .string("s"), "task": .string(long)]),
            .object(["name": .string("A"), "scope": .string("s"), "task": .string("second"), "dependencies": .array([.string("A")])]),
        ]
        let validated = try SwiftCodeMCPHost.workersValidate(workers)
        #expect(validated[0].task.count == 500 && validated[0].task.hasSuffix("..."))
        #expect(validated[1].name == "A-2")
        #expect(validated[1].scope == "s (A-2)")
        #expect(throws: MCPToolError.self) {
            _ = try SwiftCodeMCPHost.workersValidate([.object(["name": .string("A"), "task": .string("t"), "dependencies": .array([.string("B")])])])
        }
        #expect(throws: MCPToolError.self) {
            _ = try SwiftCodeMCPHost.workersValidate([.object(["name": .string("A")])])
        }
        #expect(throws: MCPToolError.self) { _ = try SwiftCodeMCPHost.workersValidate([]) }
    }

    @Test func workersTopologicalOrderAndCycle() throws {
        let ordered = try SwiftCodeMCPHost.workersTopologicalOrder([
            .init(name: "B", task: "b", scope: nil, targetFiles: [], dependencies: ["A"]),
            .init(name: "A", task: "a", scope: nil, targetFiles: [], dependencies: []),
        ])
        #expect(ordered.map(\.name) == ["A", "B"])
        #expect(throws: MCPToolError.self) {
            _ = try SwiftCodeMCPHost.workersTopologicalOrder([
                .init(name: "A", task: "a", scope: nil, targetFiles: [], dependencies: ["B"]),
                .init(name: "B", task: "b", scope: nil, targetFiles: [], dependencies: ["A"]),
            ])
        }
    }

    @Test func workersPlanPersistsThenFailsHonestlyWithoutRuntime() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("use_workers", ["workers": .array([
            .object(["name": .string("A"), "scope": .string("x"), "task": .string("do it")]),
        ])])
        #expect(r.isToolError && r.resultText.contains("worker runtime"))
        #expect(r.resultText.contains(".assist_temp/workers/"))
        let workersDir = URL(fileURLWithPath: sample.path(".assist_temp/workers"))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: workersDir.path)) ?? []
        #expect(files.count == 1 && files[0].hasSuffix(".json"))
    }

    @Test func workersRunWithStubExecutor() async throws {
        struct Stub: SwiftCodeMCPHost.FailingToolsWorkerExecutor {
            func execute(plan: SwiftCodeMCPHost.FailingToolsWorkerPlan) async throws -> [String] {
                plan.order.map { "done: \($0.name)" }
            }
        }
        SwiftCodeMCPHost.workersTestExecutor = Stub()
        defer { SwiftCodeMCPHost.workersTestExecutor = nil }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("use_workers", ["workers": .array([
            .object(["name": .string("A"), "scope": .string("x"), "task": .string("do it")]),
        ])])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.resultText.contains("done: A"))
    }

    @Test func reverseFrameParsing() throws {
        let id = "req-1"
        let good = """
        {"version":1,"id":"req-1","type":"progress","progress":{"phase":"running"}}
        {"version":1,"id":"req-1","type":"result","evidence":{"evidence_id":"ev-1","operation":"inspect_artifact"}}
        """
        let evidence = try SwiftCodeMCPHost.reverseParseFrames(good, requestID: id, stderr: "", exitCode: 0)
        #expect(evidence["evidence_id"] as? String == "ev-1")
        let errFrame = """
        {"version":1,"id":"req-1","type":"error","error":{"code":"reverse_cli_failed","message":"boom","remediation":"retry"}}
        """
        #expect(throws: MCPToolError.self) { _ = try SwiftCodeMCPHost.reverseParseFrames(errFrame, requestID: id, stderr: "", exitCode: 0) }
        #expect(throws: MCPToolError.self) {
            _ = try SwiftCodeMCPHost.reverseParseFrames(#"{"version":1,"id":"other","type":"result","evidence":{}}"#, requestID: id, stderr: "", exitCode: 0)
        }
        #expect(throws: MCPToolError.self) {
            _ = try SwiftCodeMCPHost.reverseParseFrames(#"{"version":2,"id":"req-1","type":"result","evidence":{"evidence_id":"e","operation":"o"}}"#, requestID: id, stderr: "", exitCode: 0)
        }
        #expect(throws: MCPToolError.self) { _ = try SwiftCodeMCPHost.reverseParseFrames("", requestID: id, stderr: "died", exitCode: 1) }
    }

    @Test func reverseEvidenceRendering() {
        let md = SwiftCodeMCPHost.reverseRenderEvidence([
            "evidence_id": "ev-9", "operation": "inspect_macho", "provider": "rea",
            "confidence": 0.9,
            "findings": [["title": "F1", "summary": "s1"]],
        ])
        #expect(md.contains("ev-9") && md.contains("inspect_macho") && md.contains("F1"))
    }

    @Test func reverseSanitizedEnvironmentStripsSecrets() {
        let env = SwiftCodeMCPHost.reverseSanitizedEnvironment()
        for key in env.keys {
            #expect(!key.uppercased().contains("API_KEY"))
            #expect(!key.uppercased().contains("SECRET"))
        }
    }

    @Test func reverseAnalyzeWithStubBridge() async throws {
        SwiftCodeMCPHost.reverseBridgeTestRunner = { request in
            let id = request["id"] as? String ?? "?"
            return """
            {"version":1,"id":"\(id)","type":"result","evidence":{"evidence_id":"ev-stub","operation":"inspect_artifact","provider":"rea","confidence":0.5}}
            """
        }
        defer { SwiftCodeMCPHost.reverseBridgeTestRunner = nil }
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "artifact.bin", "fake-binary")
        let host = try await openHost(sample)
        let r = try await host.server.callTool("reverse_analyze", [
            "targetPath": .string(sample.path("artifact.bin")),
            "operation": .string("inspect_artifact"), "task": .string("inspect structure"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["evidence_id"]?.string == "ev-stub")
    }

    func parseYAML(_ text: String) async throws -> AnyJSON {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("parse_yaml", ["yaml": .string(text)])
        #expect(!r.isToolError, "\(r.resultText)")
        return r.structured ?? .null
    }

    @Test func yamlBlockScalars() async throws {
        let lit = try await parseYAML("desc: |\n  line one\n  line two\nnext: 1\n")
        #expect(lit["desc"]?.string == "line one\nline two\n")
        let folded = try await parseYAML("desc: >\n  one\n  two\n\n  three\n")
        #expect(folded["desc"]?.string == "one two\nthree\n")
        let strip = try await parseYAML("desc: |-\n  a\n  b\n")
        #expect(strip["desc"]?.string == "a\nb")
        let keep = try await parseYAML("desc: |+\n  a\n\n\n")
        #expect(keep["desc"]?.string == "a\n\n\n")
    }

    @Test func yamlAnchorsAliasesAndMergeKeys() async throws {
        let doc = try await parseYAML("""
        defaults: &d
          retries: 3
          timeout: 5
        prod:
          <<: *d
          timeout: 9
        copy: *d
        """)
        #expect(doc["prod"]?["retries"]?.int == 3)
        #expect(doc["prod"]?["timeout"]?.int == 9)
        #expect(doc["copy"]?["retries"]?.int == 3)
        let seq = try await parseYAML("base: &b [1, 2]\nref: *b\n")
        #expect(seq["ref"]?.array?.count == 2)
    }

    @Test func yamlUnknownAliasAndTagsStillFail() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let alias = try await host.server.callTool("parse_yaml", ["yaml": .string("x: *missing\n")])
        #expect(alias.isToolError && alias.resultText.contains("unknown alias"))
        let tag = try await host.server.callTool("parse_yaml", ["yaml": .string("x: !custom v\n")])
        #expect(tag.isToolError && tag.resultText.contains("unsupported YAML construct"))
    }

    @Test func imageMagickPathResolution() {
        if SwiftCodeMCPHost.mediaImageMagickPath() == nil {
            #expect(SwiftCodeMCPHost.mediaImageMagickPath() == nil)
        } else {
            #expect(FileManager.default.isExecutableFile(atPath: SwiftCodeMCPHost.mediaImageMagickPath()!))
        }
    }

    @Test func imageConvertWithoutImageMagickKeepsMacOSOnlyMessage() async throws {
        guard SwiftCodeMCPHost.mediaImageMagickPath() == nil else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "a.png", "not-a-real-png")
        let host = try await openHost(sample)
        let r = try await host.server.callTool("image_convert_format", ["path": .string("a.png"), "format": .string("jpeg")])
        #expect(r.isToolError)
        #expect(r.firstText == "image_convert_format is only available on macOS.")
    }

    @Test func screenshotRegionWithoutRectStillNamesOverlay() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("take_screenshot", ["capture_mode": .string("region")])
        #expect(r.isToolError && r.resultText.contains("region-selection overlay"))
    }

    @Test func screenshotWindowWithoutIDFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let r = try await host.server.callTool("take_screenshot", ["capture_mode": .string("window")])
        #expect(r.isToolError && r.resultText.contains("window_id"))
    }

    @Test func screenrecordValidationErrors() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openHost(sample)
        let badDuration = try await host.server.callTool("take_screenrecord", ["app_identifier": .string("com.apple.finder"),
                                                                               "recording_duration": .double(0)])
        #expect(badDuration.isToolError && badDuration.resultText.contains("between 1 and 60 seconds"))
        let badFormat = try await host.server.callTool("take_screenrecord", ["app_identifier": .string("com.apple.finder"),
                                                                             "output_format": .string("avi")])
        #expect(badFormat.isToolError && badFormat.resultText.contains("Unsupported output_format"))
    }
}
