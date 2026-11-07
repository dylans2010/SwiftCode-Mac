import Foundation
import Testing
import YcodeAssistant
import YcodeIDECore
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeAgenticCodeTests {
    static let agenticCodeIDs = ["generate_code", "refactor_code", "explain_code", "review_code", "detect_bugs",
                                 "fix_bugs", "generate_unit_tests", "generate_integration_tests",
                                 "generate_documentation", "generate_comments", "code_analysis", "code_index",
                                 "project_indexing", "project_audit", "security_scan", "license_scan"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticCodeTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticCodeTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticCodeTools
        #expect(tools.map(\.name) == Self.agenticCodeIDs)
        let expectedTitles: [String: String] = [
            "generate_code": "Generate Code", "refactor_code": "Refactor Code", "explain_code": "Explain Code",
            "review_code": "Review Code", "detect_bugs": "Detect Bugs", "fix_bugs": "Fix Bugs",
            "generate_unit_tests": "Generate Unit Tests", "generate_integration_tests": "Generate Integration Tests",
            "generate_documentation": "Generate Documentation", "generate_comments": "Generate Comments",
            "code_analysis": "Code Analysis", "code_index": "Code Index", "project_indexing": "Project Indexing",
            "project_audit": "Project Audit", "security_scan": "Security Scan", "license_scan": "License Scan",
        ]
        let expectedDescriptions: [String: String] = [
            "generate_code": "Generates code based on a prompt.",
            "refactor_code": "Refactors code based on instructions.",
            "explain_code": "Explains code using AI.",
            "review_code": "Reviews code using AI.",
            "detect_bugs": "Detects bugs in Swift code.",
            "fix_bugs": "Fixes bugs in Swift code.",
            "generate_unit_tests": "Generates unit tests for the provided code.",
            "generate_integration_tests": "Generates integration tests for the provided code.",
            "generate_documentation": "Generates documentation for the provided code.",
            "generate_comments": "Generates comments for the provided code.",
            "code_analysis": "Analyzes Swift code for potential issues, complexity, and architectural patterns.",
            "code_index": "Indexes the code in a project.",
            "project_indexing": "Indexes the project to allow for fast semantic searches and relationship mapping.",
            "project_audit": "Performs a full audit of the project.",
            "security_scan": "Performs a security scan on the project.",
            "license_scan": "Scans the project for dependency licenses.",
        ]
        let expectedRequired: [String: [String]] = [
            "generate_code": ["prompt"], "refactor_code": ["code", "instructions"], "explain_code": ["code"],
            "review_code": ["code"], "detect_bugs": ["code"], "fix_bugs": ["code", "issue"],
            "generate_unit_tests": ["code"], "generate_integration_tests": ["code"],
            "generate_documentation": ["code"], "generate_comments": ["code"], "code_analysis": ["path"],
            "code_index": ["projectPath"], "project_indexing": ["root_path"], "project_audit": ["projectPath"],
            "security_scan": ["projectPath"], "license_scan": ["projectPath"],
        ]
        let expectedOutputs: [String: [String]] = [
            "generate_code": [], "refactor_code": [], "review_code": [], "fix_bugs": [],
            "generate_unit_tests": [], "generate_integration_tests": [], "generate_documentation": [],
            "generate_comments": [],
            "explain_code": ["explanation"],
            "detect_bugs": ["findingCount", "findings"],
            "code_analysis": ["blankLines", "codeLines", "commentLines", "complexity", "decisionPoints",
                              "fileCount", "forceUnwrapCount", "functionCount", "issueCount", "issues",
                              "patterns", "suggestions", "todoCount", "totalLines", "typeCount"],
            "code_index": ["actorCount", "classCount", "enumCount", "fileCount", "functionCount",
                           "protocolCount", "structCount", "symbolCount", "symbols"],
            "project_indexing": ["actorCount", "classCount", "enumCount", "fileCount", "functionCount",
                                 "protocolCount", "structCount", "symbolCount", "symbols"],
            "project_audit": ["checkCount", "failureCount", "findings", "forceUnwrapCount", "hasLicense",
                              "hasReadme", "secretFindingCount", "swiftFileCount", "testFileCount",
                              "todoCount", "totalLines"],
            "security_scan": ["filesScanned", "filesWithFindings", "findingCount", "findings"],
            "license_scan": ["dependencies", "dependencyCount", "filesScanned", "licenseFileCount",
                             "licenseFiles", "spdxCount", "spdxIdentifiers"],
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.description == expectedDescriptions[tool.name], "\(tool.name) description is not Legacy-verbatim")
            #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes,
                    "\(tool.name) must be a read-only tool")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
        }
        let installed = Set(host.agenticCodeTools.map(\.name))
        host.server.tools = host.server.tools.filter { !installed.contains($0.name) } + host.agenticCodeTools
        let served = host.server.tools.map(\.name)
        for id in Self.agenticCodeIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
        #expect(served.contains("call_hierarchy"), "call_hierarchy must already be served (Wave 3)")
        #expect(served.contains("dependency_graph"), "dependency_graph must already be served (Wave 3)")
        #expect(served.contains("semantic_query_engine"), "semantic_query_engine must already be served (Wave 3)")
        #expect(served.contains("symbol_reference_graph"), "symbol_reference_graph must already be served (Wave 3)")
        #expect(!tools.map(\.name).contains("call_hierarchy"))
        #expect(!tools.map(\.name).contains("dependency_graph"))
        #expect(!tools.map(\.name).contains("semantic_code_search"))
        #expect(!tools.map(\.name).contains("cross_reference_search"))
    }

    @Test func honestlyFailingToolsNameTheLLMPrerequisite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let cases: [(String, [String: AnyJSON])] = [
            ("generate_code", ["prompt": .string("a greeter struct")]),
            ("refactor_code", ["code": .string("func f() {}"), "instructions": .string("extract a method")]),
            ("review_code", ["code": .string("func f() {}")]),
            ("fix_bugs", ["code": .string("func f() {}"), "issue": .string("it crashes")]),
            ("generate_unit_tests", ["code": .string("struct Greeter {}")]),
            ("generate_integration_tests", ["code": .string("struct Greeter {}")]),
            ("generate_documentation", ["code": .string("struct Greeter {}")]),
            ("generate_comments", ["code": .string("struct Greeter {}")]),
        ]
        for (name, args) in cases {
            let r = try await host.server.callTool(name, args)
            #expect(r.isToolError, "\(name) must fail honestly, not fake output")
            #expect(r.firstText.contains("unavailable"), "\(name) message: \(r.firstText)")
            #expect(r.firstText.contains("LLM"), "\(name) message must name the LLM prerequisite: \(r.firstText)")
            #expect(r.structured == nil, "\(name) must return no structured content")
        }
    }

    @Test func explainCodeGivesStaticExplanation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("explain_code", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing code"))
        let code = sample.read("Sources/Greeter/Greeter.swift")
        let r = try await host.server.callTool("explain_code", ["code": .string(code)])
        #expect(!r.isToolError, "\(r.firstText)")
        let explanation = r.structured?["explanation"]?.string ?? ""
        #expect(explanation.contains("no LLM explanation is available"))
        #expect(explanation.contains("Lines: 15"))
        #expect(explanation.contains("Imports: none."))
        #expect(explanation.contains("Types: struct Greeter."))
        #expect(explanation.contains("Functions: greeting."))
        #expect(r.firstText.contains("Static analysis of supplied code"))
    }

    @Test func detectBugsScansSuppliedCode() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("detect_bugs", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing code"))
        let buggy = "struct Foo {\n    func bar() -> String {\n        let x: String? = nil\n        return x!\n    }\n}"
        let r = try await host.server.callTool("detect_bugs", ["code": .string(buggy)])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.structured?["findingCount"]?.int == 1)
        #expect((r.structured?["findings"]?.string ?? "").contains("line 4 [force unwrap (!)]"))
        #expect(r.firstText.contains("1 finding(s)"))
        let clean = "struct Foo {\n    func bar(flag: Bool) -> String {\n        if !flag { return \"Hello, Ada!\" }\n        return \"ok\"\n    }\n}"
        let ok = try await host.server.callTool("detect_bugs", ["code": .string(clean)])
        #expect(!ok.isToolError, "\(ok.firstText)")
        #expect(ok.structured?["findingCount"]?.int == 0)
        #expect(ok.firstText.contains("no bug patterns found"))
        let forced = "let a = try! foo()\nlet b = foo() as! Bar\nfatalError(\"boom\")"
        let forcedResult = try await host.server.callTool("detect_bugs", ["code": .string(forced)])
        #expect(forcedResult.structured?["findingCount"]?.int == 3)
        let forcedFindings = forcedResult.structured?["findings"]?.string ?? ""
        #expect(forcedFindings.contains("[force try (try!)]"))
        #expect(forcedFindings.contains("[force cast (as!)]"))
        #expect(forcedFindings.contains("[fatalError / preconditionFailure call]"))
        let emptyCatch = "do {\n    try foo()\n} catch {\n}"
        let catchResult = try await host.server.callTool("detect_bugs", ["code": .string(emptyCatch)])
        #expect((catchResult.structured?["findings"]?.string ?? "").contains("[empty catch block]"))
    }

    @Test func codeAnalysisReportsRealNumbers() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("code_analysis", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing path argument"))
        let escaping = try await host.server.callTool("code_analysis", ["path": .string("../..")])
        #expect(escaping.isToolError && escaping.firstText.contains("Invalid path"))
        let gone = try await host.server.callTool("code_analysis", ["path": .string("NoSuchDir")])
        #expect(gone.isToolError && gone.firstText.contains("Path not found: NoSuchDir"))
        let r = try await host.server.callTool("code_analysis", ["path": .string(".")])
        #expect(!r.isToolError, "\(r.firstText)")
        let s = r.structured
        #expect(s?["fileCount"]?.int == 5)
        #expect(s?["totalLines"]?.int == 68)
        #expect(s?["codeLines"]?.int == 44)
        #expect(s?["commentLines"]?.int == 10)
        #expect(s?["blankLines"]?.int == 14)
        #expect(s?["functionCount"]?.int == 3)
        #expect(s?["typeCount"]?.int == 3)
        #expect(s?["decisionPoints"]?.int == 5)
        #expect(s?["complexity"]?.string == "Low")
        #expect(s?["patterns"]?.string == "SwiftUI, Testing")
        #expect(s?["issueCount"]?.int == 0)
        #expect(s?["forceUnwrapCount"]?.int == 0)
        #expect(s?["todoCount"]?.int == 0)
        #expect(s?["issues"]?.string == "")
        #expect(s?["suggestions"]?.string == "No major suggestions.")
        #expect(r.firstText.contains("Analysis for .:"))
        #expect(r.firstText.contains("Complexity: Low"))
        #expect(r.firstText.contains("Patterns: SwiftUI, Testing"))
        #expect(r.firstText.contains("Potential Issues: None found."))
    }

    @Test func codeIndexBuildsRealIndex() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("code_index", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing projectPath"))
        let r = try await host.server.callTool("code_index", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.firstText)")
        let s = r.structured
        #expect(s?["fileCount"]?.int == 5)
        #expect(s?["symbolCount"]?.int == 6)
        #expect(s?["classCount"]?.int == 1)
        #expect(s?["structCount"]?.int == 2)
        #expect(s?["enumCount"]?.int == 0)
        #expect(s?["protocolCount"]?.int == 0)
        #expect(s?["actorCount"]?.int == 0)
        #expect(s?["functionCount"]?.int == 3)
        let symbols = s?["symbols"]?.string ?? ""
        #expect(symbols.hasPrefix("struct GreetingView — Previews/GreetingView.swift:4"))
        #expect(symbols.contains("struct Greeter — Sources/Greeter/Greeter.swift:2"))
        #expect(symbols.contains("func greeting — Sources/Greeter/Greeter.swift:11"))
        #expect(symbols.contains("func testSalutation — Tests/GreeterTests/GreeterTests.swift:9"))
        #expect(r.firstText.contains("Project code indexed successfully at .: 6 symbols across 5 files."))
        let one = try await host.server.callTool("code_index", ["projectPath": .string("Sources/Greeter/Greeter.swift")])
        #expect(one.structured?["fileCount"]?.int == 1)
        #expect(one.structured?["symbolCount"]?.int == 2)
    }

    @Test func projectIndexingMatchesCodeIndex() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("project_indexing", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing root_path argument"))
        let indexed = try await host.server.callTool("code_index", ["projectPath": .string(".")])
        let r = try await host.server.callTool("project_indexing", ["root_path": .string(".")])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.structured?["symbolCount"]?.int == indexed.structured?["symbolCount"]?.int)
        #expect(r.structured?["fileCount"]?.int == 5)
        #expect(r.structured?["symbols"]?.string == indexed.structured?["symbols"]?.string)
        #expect(r.firstText.contains("Project at . has been indexed. 6 symbols found across 5 files."))
        #expect(!r.firstText.contains("124 symbols"), "must report real counts, never Legacy's hardcoded 124/42")
    }

    @Test func projectAuditRunsRealChecks() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("project_audit", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing projectPath"))
        let r = try await host.server.callTool("project_audit", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.firstText)")
        let s = r.structured
        #expect(s?["swiftFileCount"]?.int == 5)
        #expect(s?["totalLines"]?.int == 68)
        #expect(s?["testFileCount"]?.int == 1)
        #expect(s?["todoCount"]?.int == 0)
        #expect(s?["forceUnwrapCount"]?.int == 0)
        #expect(s?["secretFindingCount"]?.int == 0)
        #expect(s?["hasReadme"]?.bool == false)
        #expect(s?["hasLicense"]?.bool == false)
        #expect(s?["checkCount"]?.int == 7)
        #expect(s?["failureCount"]?.int == 2)
        let findings = s?["findings"]?.string ?? ""
        #expect(findings.contains("FAIL — README present"))
        #expect(findings.contains("FAIL — License file present"))
        #expect(findings.contains("PASS — Tests present"))
        #expect(findings.contains("PASS — Build system present"))
        #expect(r.firstText.contains("Project audit for .:"))
    }

    @Test func securityScanFindsSecretsAndHttp() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("security_scan", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing projectPath"))
        let clean = try await host.server.callTool("security_scan", ["projectPath": .string(".")])
        #expect(!clean.isToolError, "\(clean.firstText)")
        #expect(clean.structured?["findingCount"]?.int == 0)
        #expect(clean.structured?["filesScanned"]?.int == 6)
        #expect(clean.structured?["filesWithFindings"]?.int == 0)
        #expect(clean.firstText.contains("no hardcoded secrets or insecure endpoints found"))
        try writeFixture(sample, "Secrets.swift", "let apiKey = \"sk-live-123456\"\nlet endpoint = \"http://example.com/api\"\n")
        let r = try await host.server.callTool("security_scan", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.structured?["findingCount"]?.int == 2)
        #expect(r.structured?["filesWithFindings"]?.int == 1)
        let findings = r.structured?["findings"]?.string ?? ""
        #expect(findings.contains("Secrets.swift:1 [hardcoded secret (api key)]"))
        #expect(findings.contains("Secrets.swift:2 [insecure http endpoint]"))
        #expect(!findings.contains("sk-live-123456"), "findings must never output matched secret values")
        #expect(!r.firstText.contains("sk-live-123456"))
    }

    @Test func licenseScanReportsRealLicenses() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("license_scan", [:])
        #expect(missing.isToolError && missing.firstText.contains("Missing projectPath"))
        let clean = try await host.server.callTool("license_scan", ["projectPath": .string(".")])
        #expect(!clean.isToolError, "\(clean.firstText)")
        #expect(clean.structured?["licenseFileCount"]?.int == 0)
        #expect(clean.structured?["spdxCount"]?.int == 0)
        #expect(clean.structured?["dependencyCount"]?.int == 0)
        #expect(clean.structured?["filesScanned"]?.int == 5)
        #expect(clean.firstText.contains("License files (0): none found"))
        #expect(clean.firstText.contains("no Package.resolved found"))
        try writeFixture(sample, "LICENSE", "MIT License\n\nCopyright (c) 2026 Example\n")
        try writeFixture(sample, "Package.resolved",
                         "{\"pins\": [{\"identity\": \"swift-argument-parser\", \"version\": \"1.2.0\"}], \"version\": 2}\n")
        let r = try await host.server.callTool("license_scan", ["projectPath": .string(".")])
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.structured?["licenseFileCount"]?.int == 1)
        #expect((r.structured?["licenseFiles"]?.string ?? "").contains("LICENSE"))
        #expect(r.structured?["dependencyCount"]?.int == 1)
        #expect((r.structured?["dependencies"]?.string ?? "").contains("swift-argument-parser 1.2.0"))
        #expect(r.firstText.contains("LICENSE: MIT License"))
        #expect(r.firstText.contains("Dependency license terms are not determined by this scan"))
        #expect(!r.firstText.contains("permissive licenses"), "must not repeat Legacy's canned verdict")
    }
}
