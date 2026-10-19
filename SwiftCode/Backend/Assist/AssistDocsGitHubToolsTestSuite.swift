import Foundation
import os

// MARK: - Documentation & GitHub tools test suite
//
//  Follows the AssistRuntimeTestSuite / SystemIndexTestSuite pattern:
//  runAllTests() returns [RuntimeTestCaseResult] for aggregation.
//
//  Unit tests are deterministic and network-free (fixtures + pure-logic
//  hooks exposed by the tools). Live integration tests hit the real Apple
//  DocC endpoint and the real GitHub API, but are gated behind
//  SWIFTCODE_LIVE_NETWORK_TESTS=1 so ordinary runs never depend on network.

@MainActor
public final class AssistDocsGitHubToolsTestSuite: Sendable {
    public static let shared = AssistDocsGitHubToolsTestSuite()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistDocsGitHubToolsTestSuite")

    private init() {}

    public func runAllTests() async -> [RuntimeTestCaseResult] {
        var results: [RuntimeTestCaseResult] = []
        results.append(testFetchDocumentationRegistered())
        results.append(testFetchDocumentationSchema())
        results.append(testDocCandidateResolution())
        results.append(testDocCJSONParsing())
        results.append(testDocCJSONMalformed())
        results.append(testHTMLParsing())
        results.append(testAppleURLGuard())
        results.append(testGitHubRepoRegistered())
        results.append(testGitHubRepoSchema())
        results.append(testRepoURLResolution())
        results.append(testOwnerRepoValidation())
        results.append(testBinaryClassification())
        results.append(testPriorityScoring())
        results.append(testGitHubURLGuard())
        results.append(await testSystemAssetDiscovered())
        results.append(await testLiveAppleDocs())
        results.append(await testLiveGitHub())
        return results
    }

    private func result(testName: String, passed: Bool, message: String, start: Date) -> RuntimeTestCaseResult {
        RuntimeTestCaseResult(testName: testName, passed: passed, message: message,
                              duration: Date().timeIntervalSince(start))
    }

    private func liveTestsEnabled() -> Bool {
        ProcessInfo.processInfo.environment["SWIFTCODE_LIVE_NETWORK_TESTS"] == "1"
    }

    // MARK: - fetch_documentation

    func testFetchDocumentationRegistered() -> RuntimeTestCaseResult {
        let start = Date()
        let registry = AssistToolRegistry()
        guard let tool = registry.getTool("fetch_documentation") else {
            return result(testName: "fetch_documentation: registered", passed: false, message: "Tool not found in registry", start: start)
        }
        let shapeOK = tool.id.range(of: "^[A-Za-z][A-Za-z0-9_-]*$", options: .regularExpression) != nil
        let readOnlyOK = tool.riskLevel == .safeRead && tool.isReadOnly && !tool.isMutating
        let ok = shapeOK && readOnlyOK && tool.capability == .general
        return result(testName: "fetch_documentation: registered", passed: ok,
                      message: ok ? "Registered as safeRead read-only tool." : "Registration properties wrong (shape=\(shapeOK) readOnly=\(readOnlyOK))",
                      start: start)
    }

    func testFetchDocumentationSchema() -> RuntimeTestCaseResult {
        let start = Date()
        let registry = AssistToolRegistry()
        let valid = registry.validate(toolId: "fetch_documentation", arguments: ["query": "SwiftUI View", "framework": "SwiftUI"])
        let props = registry.getTool("fetch_documentation")?.parametersSchema.properties ?? [:]
        let expected = ["query", "url", "framework", "platform", "language", "includeExamples", "maxResults"]
        let missing = expected.filter { props[$0] == nil }
        let ok = valid.isValid && missing.isEmpty
        return result(testName: "fetch_documentation: schema", passed: ok,
                      message: ok ? "Schema declares all arguments; query-only input validates." : "valid=\(valid.isValid) missing=\(missing)",
                      start: start)
    }

    func testDocCandidateResolution() -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        do {
            let dotted = try AssistFetchDocumentationTool.testCandidates(query: "SwiftUI.View", framework: nil)
            if !dotted.contains("documentation/swiftui/view") { failures.append("dotted 'SwiftUI.View' -> \(dotted)") }

            let withFramework = try AssistFetchDocumentationTool.testCandidates(query: "View", framework: "SwiftUI")
            if !withFramework.contains("documentation/swiftui/view") { failures.append("framework+symbol -> \(withFramework)") }

            let frameworkRoot = try AssistFetchDocumentationTool.testCandidates(query: "SwiftUI", framework: "SwiftUI")
            if frameworkRoot != ["documentation/swiftui"] { failures.append("framework root -> \(frameworkRoot)") }

            let spaced = try AssistFetchDocumentationTool.testCandidates(query: "swiftui view", framework: nil)
            if !spaced.contains("documentation/swiftui/view") { failures.append("spaced query -> \(spaced)") }
        } catch {
            failures.append("threw: \(error)")
        }
        let ok = failures.isEmpty
        return result(testName: "fetch_documentation: candidate resolution", passed: ok,
                      message: ok ? "Dotted, framework-scoped, framework-root, and spaced queries resolve." : failures.joined(separator: "; "),
                      start: start)
    }

    func testDocCJSONParsing() -> RuntimeTestCaseResult {
        let start = Date()
        let fixture = """
        {
          "abstract": [{"type": "text", "text": "A type that represents part of your app's user interface."}],
          "metadata": {
            "navigatorTitle": [{"type": "identifier", "text": "View"}],
            "platforms": [{"name": "iOS", "introducedAt": "13.0"}, {"name": "macOS", "introducedAt": "10.15"}]
          },
          "primaryContentSections": [
            {"kind": "declarations", "declarations": [
              {"languages": ["swift"], "platforms": ["iOS"],
               "tokens": [{"kind": "keyword", "text": "protocol"}, {"kind": "text", "text": " "}, {"kind": "identifier", "text": "View"}]}
            ]},
            {"kind": "content", "content": [
              {"type": "paragraph", "inlineContent": [{"type": "text", "text": "You create custom views by declaring types that conform to the View protocol."}]},
              {"type": "codeListing", "syntax": "swift", "code": ["struct ContentView: View {", "    var body: some View {", "        Text(\\"Hello\\")", "    }", "}"]}
            ]}
          ],
          "references": {},
          "seeAlsoSections": []
        }
        """.data(using: .utf8)!
        guard let parsed = AssistFetchDocumentationTool.testParseDocCJSON(fixture, url: "https://developer.apple.com/documentation/swiftui/view") else {
            return result(testName: "fetch_documentation: DocC JSON parsing", passed: false, message: "Fixture failed to parse", start: start)
        }
        let ok = parsed.contains("View") && parsed.contains("protocol View") && parsed.contains("iOS 13.0+")
        return result(testName: "fetch_documentation: DocC JSON parsing", passed: ok,
                      message: ok ? "Title, declaration, and availability extracted." : "parsed=\(parsed)",
                      start: start)
    }

    func testDocCJSONMalformed() -> RuntimeTestCaseResult {
        let start = Date()
        let bad = "{\"not\": \"documentation\"}".data(using: .utf8)!
        let parsed = AssistFetchDocumentationTool.testParseDocCJSON(bad, url: "https://developer.apple.com/documentation/x")
        let ok = parsed == nil
        return result(testName: "fetch_documentation: malformed DocC JSON", passed: ok,
                      message: ok ? "Non-documentation payload rejected (nil)." : "parsed=\(parsed ?? "(nil)")",
                      start: start)
    }

    func testHTMLParsing() -> RuntimeTestCaseResult {
        let start = Date()
        let html = """
        <html><head><title>URLSession | Apple Developer Documentation</title>
        <meta name="description" content="An object that coordinates a group of related, network data transfer tasks.">
        </head><body><p>content</p></body></html>
        """
        let (title, description) = AssistFetchDocumentationTool.testHTMLParse(html)
        let ok = title == "URLSession" && (description ?? "").hasPrefix("An object that coordinates")
        return result(testName: "fetch_documentation: HTML fallback parsing", passed: ok,
                      message: ok ? "Title and meta description extracted." : "title=\(title ?? "nil") desc=\(description ?? "nil")",
                      start: start)
    }

    func testAppleURLGuard() -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        func allows(_ s: String) -> Bool {
            guard let url = URL(string: s) else { return false }
            return (try? AssistURLGuard.validate(url, allowedHosts: ["developer.apple.com"])) != nil
        }
        if !allows("https://developer.apple.com/documentation/swiftui/view") { failures.append("valid Apple URL rejected") }
        if allows("http://developer.apple.com/documentation/x") { failures.append("http allowed") }
        if allows("https://evil.com/documentation/x") { failures.append("non-Apple host allowed") }
        if allows("https://127.0.0.1/documentation/x") { failures.append("IP literal allowed") }
        if allows("https://localhost/documentation/x") { failures.append("localhost allowed") }
        if allows("https://user:pass@developer.apple.com/documentation/x") { failures.append("userinfo allowed") }
        if allows("https://169.254.169.254/latest/meta-data/") { failures.append("metadata IP allowed") }
        let ok = failures.isEmpty
        return result(testName: "fetch_documentation: URL/SSRF guard", passed: ok,
                      message: ok ? "HTTPS-only, allow-listed host, no IPs/localhost/userinfo." : failures.joined(separator: "; "),
                      start: start)
    }

    // MARK: - github_repo

    func testGitHubRepoRegistered() -> RuntimeTestCaseResult {
        let start = Date()
        let registry = AssistToolRegistry()
        guard let tool = registry.getTool("github_repo") else {
            return result(testName: "github_repo: registered", passed: false, message: "Tool not found in registry", start: start)
        }
        let ops = tool.supportedOperations
        let expectedOps = ["repository_info", "list_files", "get_file", "get_directory", "get_tree", "search_code", "fetch_repository"]
        let missing = expectedOps.filter { !ops.contains($0) }
        let ok = tool.riskLevel == .safeRead && tool.isReadOnly && missing.isEmpty && tool.capability == .repositoryDiscovery
        return result(testName: "github_repo: registered", passed: ok,
                      message: ok ? "Registered as safeRead repositoryDiscovery tool with all 7 operations." : "missingOps=\(missing) risk=\(tool.riskLevel)",
                      start: start)
    }

    func testGitHubRepoSchema() -> RuntimeTestCaseResult {
        let start = Date()
        let registry = AssistToolRegistry()
        let missingOp = registry.validate(toolId: "github_repo", arguments: ["owner": "o", "repo": "r"])
        let valid = registry.validate(toolId: "github_repo", arguments: ["operation": "repository_info", "owner": "o", "repo": "r"])
        let badType = registry.validate(toolId: "github_repo", arguments: ["operation": "get_tree", "maxResults": "fifty"])
        let ok = !missingOp.isValid && valid.isValid && !badType.isValid
        return result(testName: "github_repo: schema validation", passed: ok,
                      message: ok ? "'operation' required; wrong-typed maxResults rejected." : "missingOp=\(missingOp.isValid) valid=\(valid.isValid) badType=\(badType.isValid)",
                      start: start)
    }

    func testRepoURLResolution() -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        do {
            let (o1, r1) = try AssistGitHubRepoTool.testResolveRepo(owner: "dylans2010", repo: "SwiftCode-Mac", url: nil)
            if o1 != "dylans2010" || r1 != "SwiftCode-Mac" { failures.append("owner+repo -> \(o1)/\(r1)") }

            let (o2, r2) = try AssistGitHubRepoTool.testResolveRepo(owner: nil, repo: nil, url: "https://github.com/dylans2010/SwiftCode-Mac")
            if o2 != "dylans2010" || r2 != "SwiftCode-Mac" { failures.append("plain URL -> \(o2)/\(r2)") }

            let (o3, r3) = try AssistGitHubRepoTool.testResolveRepo(owner: nil, repo: nil, url: "https://github.com/dylans2010/SwiftCode-Mac.git")
            if r3 != "SwiftCode-Mac" { failures.append(".git URL -> \(o3)/\(r3)") }

            let (o4, r4) = try AssistGitHubRepoTool.testResolveRepo(owner: nil, repo: nil, url: "https://github.com/dylans2010/SwiftCode-Mac/tree/main/SwiftCode")
            if o4 != "dylans2010" || r4 != "SwiftCode-Mac" { failures.append("tree URL -> \(o4)/\(r4)") }

            for bad in ["https://evil.com/dylans2010/SwiftCode-Mac",
                        "http://github.com/dylans2010/SwiftCode-Mac",
                        "https://github.com/onlyone",
                        "https://github.com/a/../b"] {
                if (try? AssistGitHubRepoTool.testResolveRepo(owner: nil, repo: nil, url: bad)) != nil {
                    failures.append("bad URL accepted: \(bad)")
                }
            }
            if (try? AssistGitHubRepoTool.testResolveRepo(owner: nil, repo: nil, url: nil)) != nil {
                failures.append("empty reference accepted")
            }
        } catch {
            failures.append("threw: \(error)")
        }
        let ok = failures.isEmpty
        return result(testName: "github_repo: repo reference resolution", passed: ok,
                      message: ok ? "owner+repo and URL forms resolve; hostile URLs rejected." : failures.joined(separator: "; "),
                      start: start)
    }

    func testOwnerRepoValidation() -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        if !AssistGitHubRepoTool.testValidateOwnerRepo(owner: "dylans2010", repo: "SwiftCode-Mac") { failures.append("valid rejected") }
        if !AssistGitHubRepoTool.testValidateOwnerRepo(owner: "org_1.2", repo: "r-e_p.o") { failures.append("valid chars rejected") }
        for (o, r) in [("a/../b", "r"), ("o", "r/r"), ("o", ""), ("", "r"), ("o", String(repeating: "x", count: 101))] {
            if AssistGitHubRepoTool.testValidateOwnerRepo(owner: o, repo: r) { failures.append("invalid accepted: '\(o)'/'\(r)'") }
        }
        let ok = failures.isEmpty
        return result(testName: "github_repo: owner/repo validation", passed: ok,
                      message: ok ? "Traversal, slashes, empties, and overlong names rejected." : failures.joined(separator: "; "),
                      start: start)
    }

    func testBinaryClassification() -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        if !AssistGitHubRepoTool.testIsBinary(path: "Assets/icon.png", data: Data()) { failures.append("png not binary") }
        if !AssistGitHubRepoTool.testIsBinary(path: "a.zip", data: Data()) { failures.append("zip not binary") }
        if AssistGitHubRepoTool.testIsBinary(path: "main.swift", data: Data("let x = 1\n".utf8)) { failures.append("swift flagged binary") }
        if !AssistGitHubRepoTool.testIsBinary(path: "notes", data: Data([0x41, 0x00, 0x42])) { failures.append("NUL bytes not binary") }
        if AssistGitHubRepoTool.testIsBinary(path: "README.md", data: Data("# Hi\n".utf8)) { failures.append("markdown flagged binary") }
        let ok = failures.isEmpty
        return result(testName: "github_repo: binary classification", passed: ok,
                      message: ok ? "Extension + NUL-byte sniffing behave." : failures.joined(separator: "; "),
                      start: start)
    }

    func testPriorityScoring() -> RuntimeTestCaseResult {
        let start = Date()
        let queryHit = AssistGitHubRepoTool.testPriorityScore(path: "SwiftCode/Backend/Assist/Tools/AssistTool.swift", query: "AssistTool")
        let packageSwift = AssistGitHubRepoTool.testPriorityScore(path: "Package.swift", query: "")
        let random = AssistGitHubRepoTool.testPriorityScore(path: "docs/notes/todo.txt", query: "")
        let ok = queryHit > random && packageSwift > random
        return result(testName: "github_repo: fetch prioritization", passed: ok,
                      message: ok ? "Query hits and project config outrank unrelated files." : "scores: query=\(queryHit) package=\(packageSwift) random=\(random)",
                      start: start)
    }

    func testGitHubURLGuard() -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        if !AssistGitHubRepoTool.testURLGuardAllows("https://api.github.com/repos/o/r") { failures.append("api.github.com rejected") }
        if !AssistGitHubRepoTool.testURLGuardAllows("https://raw.githubusercontent.com/o/r/main/f") { failures.append("raw.githubusercontent.com rejected") }
        if AssistGitHubRepoTool.testURLGuardAllows("https://api.github.com.evil.com/repos") { failures.append("lookalike host allowed") }
        if AssistGitHubRepoTool.testURLGuardAllows("https://[::1]/x") { failures.append("IPv6 allowed") }
        let ok = failures.isEmpty
        return result(testName: "github_repo: URL/SSRF guard", passed: ok,
                      message: ok ? "GitHub hosts allow-listed; lookalikes and IPs rejected." : failures.joined(separator: "; "),
                      start: start)
    }

    // MARK: - System Asset

    func testSystemAssetDiscovered() async -> RuntimeTestCaseResult {
        let start = Date()
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("test_docs_github_assets_\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer {
                try? fm.removeItem(at: tempDir)
                Task { await SystemIndexService.shared.setCustomAssetsDirectory(nil) }
            }
            // Source the asset from the app bundle (preferred) or the dev tree.
            let assetName = "DocumentationWithGitHub.md"
            var sourceURL: URL? = nil
            if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("System Assets/\(assetName)"),
               fm.fileExists(atPath: resourceURL.path) {
                sourceURL = resourceURL
            } else {
                for candidate in [
                    "/System Assets/\(assetName)",
                    "/Backend/Assist/Functions/System Assets/\(assetName)",
                    "/SwiftCode/Backend/Assist/Functions/System Assets/\(assetName)"
                ] {
                    let execDir = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
                    let url = URL(fileURLWithPath: execDir + candidate)
                    if fm.fileExists(atPath: url.path) { sourceURL = url; break }
                }
            }
            guard let sourceURL else {
                return result(testName: "DocumentationWithGitHub.md: indexed", passed: false,
                              message: "Asset not found in bundle or dev tree", start: start)
            }
            try fm.copyItem(at: sourceURL, to: tempDir.appendingPathComponent(assetName))
            await SystemIndexService.shared.setCustomAssetsDirectory(tempDir)
            await SystemIndexService.shared.rebuildIndex()
            let diag = await SystemIndexService.shared.diagnostics()
            guard diag.discoveredFiles.contains(assetName) else {
                return result(testName: "DocumentationWithGitHub.md: indexed", passed: false,
                              message: "Not discovered; found: \(diag.discoveredFiles)", start: start)
            }
            let text = await SystemIndexService.shared.assetText(forRelativePath: assetName)
            guard (text?.contains("fetch_documentation") == true) && (text?.contains("github_repo") == true) else {
                return result(testName: "DocumentationWithGitHub.md: indexed", passed: false,
                              message: "Asset text missing tool references", start: start)
            }
            // Retrieval: a relevant query should surface this asset's sections.
            let query = InstructionQueryContext(
                userText: "inspect this github repository and check the apple documentation for the api",
                taskCategory: .toolUse,
                stage: .preparation,
                maxTokens: 2000
            )
            let retrieval = await SystemIndexService.shared.retrieve(for: query)
            let surfaced = retrieval.retrievals.contains { $0.documentPath == assetName }
            return result(testName: "DocumentationWithGitHub.md: indexed", passed: surfaced,
                          message: surfaced
                            ? "Discovered, indexed, and retrieved for a docs+github query (\(retrieval.retrievals.count) sections)."
                            : "Indexed but not retrieved for a relevant query",
                          start: start)
        } catch {
            return result(testName: "DocumentationWithGitHub.md: indexed", passed: false,
                          message: "threw: \(error.localizedDescription)", start: start)
        }
    }

    // MARK: - Live integration (gated)

    func testLiveAppleDocs() async -> RuntimeTestCaseResult {
        let start = Date()
        guard liveTestsEnabled() else {
            return result(testName: "fetch_documentation: live Apple DocC", passed: true,
                          message: "SKIPPED (set SWIFTCODE_LIVE_NETWORK_TESTS=1 to run)", start: start)
        }
        do {
            var options = AssistFetchOptions()
            options.allowedHosts = ["developer.apple.com"]
            options.acceptedContentTypes = ["application/json"]
            let url = URL(string: "https://developer.apple.com/tutorials/data/documentation/swiftui/view.json")!
            let response = try await AssistSecureHTTPClient.shared.get(url, options: options)
            let parsed = AssistFetchDocumentationTool.testParseDocCJSON(response.data, url: "https://developer.apple.com/documentation/swiftui/view")
            let ok = response.statusCode == 200 && (parsed?.contains("View") == true)
            return result(testName: "fetch_documentation: live Apple DocC", passed: ok,
                          message: ok ? "Live DocC JSON fetched and parsed (status 200)." : "parsed=\(parsed ?? "nil") status=\(response.statusCode)",
                          start: start)
        } catch {
            return result(testName: "fetch_documentation: live Apple DocC", passed: false,
                          message: "threw: \(error.localizedDescription)", start: start)
        }
    }

    func testLiveGitHub() async -> RuntimeTestCaseResult {
        let start = Date()
        guard liveTestsEnabled() else {
            return result(testName: "github_repo: live GitHub API", passed: true,
                          message: "SKIPPED (set SWIFTCODE_LIVE_NETWORK_TESTS=1 to run)", start: start)
        }
        do {
            var options = AssistFetchOptions()
            options.allowedHosts = ["api.github.com"]
            options.acceptedContentTypes = ["application/json"]
            let url = URL(string: "https://api.github.com/repos/dylans2010/SwiftCode-Mac")!
            let response = try await AssistSecureHTTPClient.shared.get(url, options: options)
            guard let obj = try? AssistJSON.parse(response.data),
                  let d = AssistJSON.object(obj),
                  let fullName = d["full_name"] as? String else {
                return result(testName: "github_repo: live GitHub API", passed: false, message: "Metadata did not parse", start: start)
            }
            let treeURL = URL(string: "https://api.github.com/repos/dylans2010/SwiftCode-Mac/git/trees/main?recursive=1")!
            var treeOptions = options
            treeOptions.maxResponseBytes = 10_000_000
            let treeResponse = try await AssistSecureHTTPClient.shared.get(treeURL, options: treeOptions)
            guard let treeObj = try? AssistJSON.parse(treeResponse.data),
                  let tree = AssistJSON.object(treeObj),
                  let entries = AssistJSON.array(tree["tree"]) else {
                return result(testName: "github_repo: live GitHub API", passed: false, message: "Tree did not parse", start: start)
            }
            let ok = fullName == "dylans2010/SwiftCode-Mac" && !entries.isEmpty
            return result(testName: "github_repo: live GitHub API", passed: ok,
                          message: ok ? "repository_info + recursive tree OK (\(entries.count) entries, truncated=\(tree["truncated"] as? Bool ?? false))." : "fullName=\(fullName)",
                          start: start)
        } catch {
            return result(testName: "github_repo: live GitHub API", passed: false,
                          message: "threw: \(error.localizedDescription)", start: start)
        }
    }
}
