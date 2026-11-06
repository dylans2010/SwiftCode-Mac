import Foundation
import YcodeAssistant
import YcodeIDECore

/// The ported Legacy Agentic code-generation & analysis tools
/// (Wave 8, slice F).
///
/// Behaviour source: Legacy's `SwiftCode/Tools/Agentic/`
/// `GenerateCodeTool`, `RefactorCodeTool`, `ExplainCodeTool`,
/// `ReviewCodeTool`, `DetectBugsTool`, `FixBugsTool`,
/// `GenerateUnitTestsTool`, `GenerateIntegrationTestsTool`,
/// `GenerateDocumentationTool`, `GenerateCommentsTool`,
/// `CodeAnalysisTool`, `CodeIndexTool`, `ProjectIndexingTool`,
/// `ProjectAuditTool`, `SecurityScanTool`, `LicenseScanTool`
/// (Dylan's own code, ported under MIT), as specified in
/// `specs/ide/agentic-code-draft.md`. Four tools from the slice are
/// NOT in this array: `call_hierarchy` and `dependency_graph` are
/// already served by the Wave 3 ports of the same IDs
/// (`YcodeTools+Search.swift`), and `semantic_code_search` /
/// `cross_reference_search` are duplicates of the already-ported
/// `semantic_query_engine` / `symbol_reference_graph` — the
/// coordinator owns the alias proposals for those two.
///
/// Conventions, following Waves 1–3 and 6:
///
/// * Schemas are Legacy's `parametersSchema` verbatim (types and
///   `required` lists), plus the `workspace` parameter Wave 1 adds
///   to every tool. Legacy's Agentic schemas carry no per-property
///   descriptions except `code_analysis.path` and
///   `project_indexing.root_path`; the descriptions on the other
///   properties are Ycode additions, recorded in the spec.
///   Legacy's parameter-name aliases are NOT supported: Ycode's
///   argument validation rejects unknown arguments before the
///   handler runs.
/// * Structured data keeps Legacy's keys where Legacy has any, with
///   typed JSON values (integers, booleans) the way Ycode's other
///   tools do — Legacy's Agentic tools return plain strings, so the
///   structured keys here are Ycode's, recorded in the spec.
/// * Path resolution for the project-scoped tools follows the
///   static-analysis slice: the strict
///   `staticAnalysisResolveScanPath` (blank → workspace root; any
///   `..` → the Legacy "Invalid path" failure; a missing root
///   fails as "Path not found"). No path is ever allowed to escape
///   the workspace. The inline-code tools (`explain_code`,
///   `detect_bugs`) take no path and need no workspace session,
///   like `docstring_generator`.
/// * All 16 tools are `readOnly: true, idempotent: true`,
///   `writes: false`. No tool in this slice writes a file. There
///   is no Autopilot bypass.
///
/// LLM tools (gap-closure wiring): the eight tools below are wired to
/// the configured Assist LLM provider through `LLMToolCompletionService`
/// (`ycode/Sources/YcodeAssistant/LLMToolCompletion.swift`) — the host's
/// own dispatch (`AssistantBackends.provider(_:)`, Wave 9 providers
/// OpenRouter / OpenCode / Hermes / Foundation Models / SwiftCode Cloud,
/// Wave 15 router selection), never a parallel client or registry.
/// Legacy itself returns canned strings for seven of them
/// (`generate_code`, `refactor_code`, `review_code`,
/// `fix_bugs`, `generate_unit_tests`,
/// `generate_integration_tests`, `generate_documentation`,
/// `generate_comments`) — a fake in Legacy, not ported as real
/// behaviour: the port sends the same request to the real provider
/// instead. With no provider usable the handler fails honestly naming
/// the provider (the message keeps the words "unavailable" and "LLM").
/// `explain_code` is the exception: Legacy really
/// calls OpenRouter, and the port implements the deterministic
/// subset the project already accepted for `intel_explain_code` —
/// a static structural explanation, labelled as such.
/// The shared service also backs `code_refactor` (see
/// `YcodeTools+FileWriting.swift`), `code_review` (see
/// `YcodeTools+ReviewDocs.swift`) and `intel_autofix` (see
/// `YcodeTools+Planning.swift`).
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `detect_bugs`: Legacy runs `/usr/bin/swiftlint lint --quiet`
///   but never passes the supplied `code` anywhere (it lints the
///   process working directory) and returns swiftlint's stdout as
///   "bugs". The port instead scans the supplied code itself for
///   crash-prone patterns (postfix force unwrap, `try!`, `as!`,
///   `fatalError` / `preconditionFailure`, empty `catch` blocks).
///   Findings are heuristic leads, not confirmed bugs; matches
///   inside strings and comments count, as in Legacy's own scans
///   — except a `!` followed by `"` is not a force unwrap (it is
///   almost always punctuation inside a string literal, e.g.
///   `"Hello, \(name)!"`).
/// * `code_analysis`: Legacy returns hardcoded mock text
///   ("Complexity: Low", "Patterns: Observable, MVVM", "Potential
///   Issues: None found."). The port computes every number from
///   the scanned sources (line classes, decision points,
///   declarations, force-unwrap and TODO counts, detected
///   patterns) and derives the complexity rating and suggestions
///   from those numbers. The decision-point count treats the
///   parameter label `for` as a branch (regex `\bfor\b`), so a
///   function `greeting(for:)` contributes one point — a known
///   heuristic quirk, stated in the spec.
/// * `code_index` / `project_indexing`: Legacy returns canned
///   success strings (`project_indexing` hardcodes "124 symbols
///   found across 42 files"). The port builds a real in-memory
///   declaration index per call (regex scan, same heuristics as
///   `dead_code_scan`) and reports the real counts. The index is
///   not persisted and has no embeddings; the spec says so.
/// * `project_audit`: Legacy returns a canned one-line report.
///   The port runs seven real checks (README, license file, tests
///   present, TODO markers, force unwraps, secrets / insecure
///   endpoints, build system) over the real file counts.
/// * `security_scan`: Legacy returns a canned "0 issues found".
///   The port scans every file it can read as UTF-8 for
///   hardcoded-secret assignments and insecure `http://`
///   endpoints. Findings report file:line:kind only and never
///   output matched secret values, as `secrets_scan` does.
/// * `license_scan`: Legacy returns a canned "All dependencies
///   use permissive licenses". The port reports the license
///   files and SPDX identifiers it actually finds plus the
///   dependency names/versions from `Package.resolved`, and
///   states plainly that dependency license terms are not
///   determined (no SPDX database or network lookup).
///
/// Wiring: the coordinator adds `agenticCodeTools` to
/// `installTools()` in `YcodeTools.swift` (this file must not edit
/// that file). The alias proposals `semantic_code_search` →
/// `semantic_query_engine` and `cross_reference_search` →
/// `symbol_reference_graph` belong in `MCPServer.toolAliases`
/// (also coordinator-owned).
extension YcodeMCPHost {
    var agenticCodeTools: [MCPTool] {
        return [
            tool("generate_code", "Generate Code",
                 "Generates code based on a prompt.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "prompt": Schema.string("Natural-language description of the code to generate.")],
                                      required: ["prompt"])) { h, call in
                try await h.agenticCodeGenerateCode(call)
            },
            tool("refactor_code", "Refactor Code",
                 "Refactors code based on instructions.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code to refactor."),
                                       "instructions": Schema.string("Natural-language description of the refactoring to perform.")],
                                      required: ["code", "instructions"])) { h, call in
                try await h.agenticCodeRefactorCode(call)
            },
            tool("explain_code", "Explain Code",
                 "Explains code using AI.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code to explain.")],
                                      required: ["code"]),
                 output: Schema.output(["explanation": Schema.str])) { h, call in
                try h.agenticCodeExplainCode(call)
            },
            tool("review_code", "Review Code",
                 "Reviews code using AI.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code to review.")],
                                      required: ["code"])) { h, call in
                try await h.agenticCodeReviewCode(call)
            },
            tool("detect_bugs", "Detect Bugs",
                 "Detects bugs in Swift code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The Swift source code to scan for bug patterns.")],
                                      required: ["code"]),
                 output: Schema.output(["findingCount": Schema.int, "findings": Schema.str])) { h, call in
                try h.agenticCodeDetectBugs(call)
            },
            tool("fix_bugs", "Fix Bugs",
                 "Fixes bugs in Swift code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code containing the bug."),
                                       "issue": Schema.string("Description of the bug to fix.")],
                                      required: ["code", "issue"])) { h, call in
                try await h.agenticCodeFixBugs(call)
            },
            tool("generate_unit_tests", "Generate Unit Tests",
                 "Generates unit tests for the provided code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code to generate unit tests for.")],
                                      required: ["code"])) { h, call in
                try await h.agenticCodeGenerateUnitTests(call)
            },
            tool("generate_integration_tests", "Generate Integration Tests",
                 "Generates integration tests for the provided code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code to generate integration tests for.")],
                                      required: ["code"])) { h, call in
                try await h.agenticCodeGenerateIntegrationTests(call)
            },
            tool("generate_documentation", "Generate Documentation",
                 "Generates documentation for the provided code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code to document.")],
                                      required: ["code"])) { h, call in
                try await h.agenticCodeGenerateDocumentation(call)
            },
            tool("generate_comments", "Generate Comments",
                 "Generates comments for the provided code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "code": Schema.string("The source code to comment.")],
                                      required: ["code"])) { h, call in
                try await h.agenticCodeGenerateComments(call)
            },
            tool("code_analysis", "Code Analysis",
                 "Analyzes Swift code for potential issues, complexity, and architectural patterns.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("The path to the file or directory to analyze.")],
                                      required: ["path"]),
                 output: Schema.output(["fileCount": Schema.int, "totalLines": Schema.int, "codeLines": Schema.int,
                                        "commentLines": Schema.int, "blankLines": Schema.int, "functionCount": Schema.int,
                                        "typeCount": Schema.int, "decisionPoints": Schema.int, "complexity": Schema.str,
                                        "patterns": Schema.str, "issueCount": Schema.int, "forceUnwrapCount": Schema.int,
                                        "todoCount": Schema.int, "issues": Schema.str, "suggestions": Schema.str])) { h, call in
                try h.agenticCodeAnalyze(call)
            },
            tool("code_index", "Code Index",
                 "Indexes the code in a project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project to index.")],
                                      required: ["projectPath"]),
                 output: Schema.output(["fileCount": Schema.int, "symbolCount": Schema.int, "classCount": Schema.int,
                                        "structCount": Schema.int, "enumCount": Schema.int, "protocolCount": Schema.int,
                                        "actorCount": Schema.int, "functionCount": Schema.int, "symbols": Schema.str])) { h, call in
                try h.agenticCodeIndex(call)
            },
            tool("project_indexing", "Project Indexing",
                 "Indexes the project to allow for fast semantic searches and relationship mapping.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "root_path": Schema.string("The root path of the project to index.")],
                                      required: ["root_path"]),
                 output: Schema.output(["fileCount": Schema.int, "symbolCount": Schema.int, "classCount": Schema.int,
                                        "structCount": Schema.int, "enumCount": Schema.int, "protocolCount": Schema.int,
                                        "actorCount": Schema.int, "functionCount": Schema.int, "symbols": Schema.str])) { h, call in
                try h.agenticCodeProjectIndexing(call)
            },
            tool("project_audit", "Project Audit",
                 "Performs a full audit of the project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project to audit.")],
                                      required: ["projectPath"]),
                 output: Schema.output(["swiftFileCount": Schema.int, "totalLines": Schema.int, "testFileCount": Schema.int,
                                        "todoCount": Schema.int, "forceUnwrapCount": Schema.int, "secretFindingCount": Schema.int,
                                        "hasReadme": Schema.bool, "hasLicense": Schema.bool, "checkCount": Schema.int,
                                        "failureCount": Schema.int, "findings": Schema.str])) { h, call in
                try h.agenticCodeAuditProject(call)
            },
            tool("security_scan", "Security Scan",
                 "Performs a security scan on the project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project to scan.")],
                                      required: ["projectPath"]),
                 output: Schema.output(["findingCount": Schema.int, "filesScanned": Schema.int,
                                        "filesWithFindings": Schema.int, "findings": Schema.str])) { h, call in
                try h.agenticCodeSecurityScan(call)
            },
            tool("license_scan", "License Scan",
                 "Scans the project for dependency licenses.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path of the project to scan.")],
                                      required: ["projectPath"]),
                 output: Schema.output(["licenseFileCount": Schema.int, "licenseFiles": Schema.str, "spdxCount": Schema.int,
                                        "spdxIdentifiers": Schema.str, "dependencyCount": Schema.int,
                                        "dependencies": Schema.str, "filesScanned": Schema.int])) { h, call in
                try h.agenticCodeLicenseScan(call)
            },
        ]
    }
}

extension YcodeMCPHost {
    // MARK: - LLM tools (wired to the configured Assist provider)

    func agenticCodeGenerateCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let prompt = call.arguments["prompt"]?.string,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing prompt")
        }
        let completion = try await llmToolComplete(
            systemPrompt: "You are a Swift code generator. Return ONLY the Swift code that implements the request, with no preamble, no explanation, and no markdown fences.",
            userText: prompt, toolName: "generate_code")
        return .text(try Self.llmToolCodeOnly(completion, toolName: "generate_code"))
    }

    func agenticCodeRefactorCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code or instructions")
        guard let instructions = call.arguments["instructions"]?.string,
              !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing code or instructions")
        }
        let completion = try await llmToolComplete(
            systemPrompt: "You are a Swift refactoring engine. Apply the requested refactoring to the supplied code. Return ONLY the refactored code, with no preamble, no explanation, and no markdown fences.",
            userText: "Instructions: \(instructions)\n\nCode:\n\(code)", toolName: "refactor_code")
        return .text(try Self.llmToolCodeOnly(completion, toolName: "refactor_code"))
    }

    func agenticCodeReviewCode(_ call: MCPToolCall) async throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code")
        let completion = try await llmToolComplete(
            systemPrompt: "You are a senior Swift code reviewer. Review the supplied Swift code for correctness, safety, Swift idioms, and maintainability. List concrete issues with line references where possible, then concrete fixes. Do not invent APIs or behaviour the code does not show. If the code is sound, say so briefly.",
            userText: code, toolName: "review_code")
        return .text(completion.text)
    }

    func agenticCodeFixBugs(_ call: MCPToolCall) async throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code or issue")
        guard let issue = call.arguments["issue"]?.string,
              !issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing code or issue")
        }
        let completion = try await llmToolComplete(
            systemPrompt: "You are a Swift debugging engine. Fix the described bug in the supplied code. Return ONLY the fixed code, with no preamble, no explanation, and no markdown fences.",
            userText: "Issue: \(issue)\n\nCode:\n\(code)", toolName: "fix_bugs")
        return .text(try Self.llmToolCodeOnly(completion, toolName: "fix_bugs"))
    }

    func agenticCodeGenerateUnitTests(_ call: MCPToolCall) async throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code")
        let completion = try await llmToolComplete(
            systemPrompt: "You are a Swift test generator. Generate XCTest unit tests (import XCTest, XCTestCase subclasses) with real assertions that exercise the supplied code's behaviour. Return ONLY the test source, with no preamble, no explanation, and no markdown fences.",
            userText: code, toolName: "generate_unit_tests")
        return .text(try Self.llmToolCodeOnly(completion, toolName: "generate_unit_tests"))
    }

    func agenticCodeGenerateIntegrationTests(_ call: MCPToolCall) async throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code")
        let completion = try await llmToolComplete(
            systemPrompt: "You are a Swift test generator. Generate XCTest integration tests (import XCTest, XCTestCase subclasses) with real assertions that exercise the supplied code's behaviour end to end, including its collaborators. Return ONLY the test source, with no preamble, no explanation, and no markdown fences.",
            userText: code, toolName: "generate_integration_tests")
        return .text(try Self.llmToolCodeOnly(completion, toolName: "generate_integration_tests"))
    }

    func agenticCodeGenerateDocumentation(_ call: MCPToolCall) async throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code")
        let completion = try await llmToolComplete(
            systemPrompt: "You are a Swift documentation writer. Write Apple DocC documentation comments (///) for the supplied code: a summary plus - Parameter, - Returns, and - Throws tags where they apply. Return ONLY the documentation comments, with no preamble, no explanation, and no markdown fences.",
            userText: code, toolName: "generate_documentation")
        return .text(try Self.llmToolCodeOnly(completion, toolName: "generate_documentation"))
    }

    func agenticCodeGenerateComments(_ call: MCPToolCall) async throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code")
        let completion = try await llmToolComplete(
            systemPrompt: "You are a Swift code commenter. Return the supplied code with concise explanatory comments added at the non-obvious points. Do not change the code itself. Return ONLY the commented code, with no preamble, no explanation, and no markdown fences.",
            userText: code, toolName: "generate_comments")
        return .text(try Self.llmToolCodeOnly(completion, toolName: "generate_comments"))
    }
}

extension YcodeMCPHost {
    // MARK: - Shared LLM service for MCP tools (gap-closure wiring)

    /// Test seam (precedent: `agenticGitTestSecretStore`): tests set a
    /// service backed by stub providers, so no live network or real
    /// credential is ever touched. Production always uses
    /// `llmToolService()` below.
    static var llmToolTestService: LLMToolCompletionService?

    /// The LLM service for MCP tools: the host's Assist dispatch
    /// (`CodingAssistantServices` — Settings' provider + model, the
    /// secret store, and any test provider override), never a parallel
    /// client or registry.
    func llmToolService() -> LLMToolCompletionService {
        if let test = Self.llmToolTestService { return test }
        let services = CodingAssistantServices.shared
        var overrides: [ProviderKind: AssistantProvider] = [:]
        if let override = services.providerOverride {
            for kind in ProviderKind.allCases {
                if let provider = override(kind) { overrides[kind] = provider }
            }
        }
        return LLMToolCompletionService(backends: services.backends(), providerOverrides: overrides)
    }

    /// One LLM completion for a tool, mapping every failure to an
    /// `MCPToolError` that keeps the words "unavailable" and "LLM".
    /// `failureNote` replaces the default "No output was produced."
    /// tail (tools with their own contract, e.g. `code_review`, name it).
    func llmToolComplete(systemPrompt: String, userText: String, toolName: String,
                         failureNote: String? = nil) async throws -> LLMToolCompletion {
        do {
            return try await llmToolService().complete(systemPrompt: systemPrompt, userText: userText)
        } catch let error as LLMToolError {
            throw MCPToolError("\(toolName) is unavailable: \(error.localizedDescription). \(failureNote ?? "No output was produced.")")
        } catch {
            throw MCPToolError("\(toolName) is unavailable: the LLM request failed: \(error.localizedDescription). \(failureNote ?? "No output was produced.")")
        }
    }

    /// Strips one surrounding markdown fence pair (Legacy's own
    /// ```swift / ``` stripping in `code_refactor` / `intel_autofix`)
    /// and trims the result.
    nonisolated static func llmToolStripFences(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            if let newline = out.firstIndex(of: "\n") {
                out = String(out[out.index(after: newline)...])
            } else {
                out = ""
            }
        }
        if out.hasSuffix("```") { out = String(out.dropLast(3)) }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A code-only reply: fences stripped; empty after stripping is an
    /// honest failure, never an empty file.
    nonisolated static func llmToolCodeOnly(_ completion: LLMToolCompletion, toolName: String) throws -> String {
        let code = llmToolStripFences(completion.text)
        guard !code.isEmpty else {
            throw MCPToolError("\(toolName) is unavailable: the \(completion.provider.displayName) LLM provider returned an empty response. No output was produced.")
        }
        return code
    }


    // MARK: - Inline-code tools

    /// The deterministic subset of Legacy's OpenRouter-backed
    /// explanation: the same static structural explanation
    /// `intel_explain_code` returns for a file, applied to the
    /// supplied code. It names its types, functions and imports; it
    /// does not understand what the code does.
    func agenticCodeExplainCode(_ call: MCPToolCall) throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code")
        let explanation = PlanningSupport.staticExplanation(of: code, at: "supplied code")
        return .structured(["explanation": .string(explanation)], summary: explanation)
    }

    /// A heuristic scan of the supplied code for crash-prone
    /// patterns. Findings are leads, not confirmed bugs.
    func agenticCodeDetectBugs(_ call: MCPToolCall) throws -> MCPToolResult {
        let code = try Self.agenticCodeRequiredCode(call, missingMessage: "Missing code")
        let lines = code.components(separatedBy: "\n")
        let findings = Self.agenticCodeBugFindings(lines)
        let capped = Array(findings.prefix(200))
        let findingText = capped.map { "line \($0.line) [\($0.kind)] — \($0.text)" }.joined(separator: "\n")
        if capped.isEmpty {
            return .structured(["findingCount": .int(0), "findings": .string("")],
                               summary: "Bug scan (heuristic) of the supplied code: no bug patterns found.")
        }
        var summary = "Bug scan (heuristic) of the supplied code: \(findings.count) finding(s).\n" + findingText
        if findings.count > capped.count {
            summary += "\n… and \(findings.count - capped.count) more finding(s) omitted (listing capped at 200)."
        }
        return .structured(["findingCount": .int(findings.count), "findings": .string(findingText)], summary: summary)
    }

    // MARK: - Code analysis and indexing

    func agenticCodeAnalyze(_ call: MCPToolCall) throws -> MCPToolResult {
        let (raw, root, scope) = try agenticCodeResolveScope(call, key: "path", missingMessage: "Missing path argument")
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scope)
        if files.isEmpty {
            return .structured(["fileCount": .int(0), "totalLines": .int(0), "codeLines": .int(0), "commentLines": .int(0),
                                "blankLines": .int(0), "functionCount": .int(0), "typeCount": .int(0), "decisionPoints": .int(0),
                                "complexity": .string("Low"), "patterns": .string("none detected"), "issueCount": .int(0),
                                "forceUnwrapCount": .int(0), "todoCount": .int(0), "issues": .string(""),
                                "suggestions": .string("No Swift files found to analyze.")],
                               summary: "Analysis for \(raw): no Swift files found.")
        }
        guard let decisionRegex = try? NSRegularExpression(pattern: "\\b(if|for|while|guard|case|catch)\\b|&&|\\|\\|", options: []) else {
            throw MCPToolError("Code Analysis: failed to build decision-point pattern.")
        }
        var totalLines = 0, codeLines = 0, commentLines = 0, blankLines = 0, decisionPoints = 0
        var forceUnwrapCount = 0, fatalCount = 0, todoCount = 0
        var declarations: [AgenticCodeDeclaration] = []
        var longest: (name: String, file: String, length: Int)?
        var hasSwiftUI = false, hasObservable = false, hasCombine = false, hasAsync = false, hasTesting = false, hasSwiftData = false
        for url in files {
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            let lines = text.components(separatedBy: "\n")
            let rel = Self.staticAnalysisRelative(url, root: root)
            totalLines += lines.count
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    blankLines += 1
                } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") {
                    commentLines += 1
                } else {
                    codeLines += 1
                }
                decisionPoints += decisionRegex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line)).count
            }
            let bugs = Self.agenticCodeBugFindings(lines)
            forceUnwrapCount += bugs.filter { $0.kind.hasPrefix("force") }.count
            fatalCount += bugs.filter { $0.kind.hasPrefix("fatalError") }.count
            todoCount += Self.agenticCodeTodoCount(lines)
            declarations.append(contentsOf: Self.agenticCodeScanDeclarations(lines))
            for span in Self.agenticCodeFunctionSpans(lines) where span.length > (longest?.length ?? 0) {
                longest = (name: span.name, file: rel, length: span.length)
            }
            if text.contains("import SwiftUI") || text.contains(": View") { hasSwiftUI = true }
            if text.contains("@Observable") || text.contains("ObservableObject") { hasObservable = true }
            if text.contains("import Combine") { hasCombine = true }
            if text.contains("async") || text.contains("await") { hasAsync = true }
            if text.contains("import XCTest") || text.contains("import Testing") { hasTesting = true }
            if text.contains("import SwiftData") || text.contains("@Model") { hasSwiftData = true }
        }
        let functionCount = declarations.filter { $0.kind == "func" }.count
        let typeCount = declarations.count - functionCount
        let average = functionCount > 0 ? Double(decisionPoints) / Double(functionCount) : 0
        let complexity = average < 3 ? "Low" : average < 8 ? "Moderate" : "High"
        var patterns: [String] = []
        if hasSwiftUI { patterns.append("SwiftUI") }
        if hasObservable { patterns.append("Observable") }
        if declarations.contains(where: { $0.kind != "func" && $0.name.hasSuffix("ViewModel") }) { patterns.append("MVVM") }
        if declarations.contains(where: { $0.kind == "actor" }) { patterns.append("Actor") }
        if hasAsync { patterns.append("Async/Await") }
        if hasCombine { patterns.append("Combine") }
        if hasTesting { patterns.append("Testing") }
        if hasSwiftData { patterns.append("SwiftData") }
        var issues: [String] = []
        if forceUnwrapCount > 0 { issues.append("\(forceUnwrapCount) force-unwrap / force-try / force-cast site(s)") }
        if fatalCount > 0 { issues.append("\(fatalCount) fatalError / preconditionFailure call(s)") }
        if todoCount > 0 { issues.append("\(todoCount) TODO / FIXME / XXX / HACK marker(s)") }
        var suggestions: [String] = []
        if forceUnwrapCount > 0 { suggestions.append("Replace force unwraps with guard let / if let.") }
        if todoCount > 0 { suggestions.append("Resolve the TODO / FIXME markers.") }
        if totalLines > 0 && Double(commentLines) / Double(totalLines) < 0.10 {
            suggestions.append("Consider adding documentation comments to public methods.")
        }
        if let longest, longest.length >= 60 {
            suggestions.append("Decompose '\(longest.name)' (\(longest.length) lines in \(longest.file)).")
        }
        if suggestions.isEmpty { suggestions.append("No major suggestions.") }
        let issueCount = forceUnwrapCount + fatalCount + todoCount
        let summary = """
        Analysis for \(raw):
        - Files: \(files.count) Swift file(s), \(totalLines) lines (\(codeLines) code, \(commentLines) comment, \(blankLines) blank)
        - Complexity: \(complexity) (\(decisionPoints) decision points across \(functionCount) functions, \(typeCount) types)
        - Patterns: \(patterns.isEmpty ? "none detected" : patterns.joined(separator: ", "))
        - Potential Issues: \(issues.isEmpty ? "None found." : issues.joined(separator: "; "))
        - Suggestions: \(suggestions.joined(separator: " "))
        """
        return .structured(["fileCount": .int(files.count), "totalLines": .int(totalLines), "codeLines": .int(codeLines),
                            "commentLines": .int(commentLines), "blankLines": .int(blankLines),
                            "functionCount": .int(functionCount), "typeCount": .int(typeCount),
                            "decisionPoints": .int(decisionPoints), "complexity": .string(complexity),
                            "patterns": .string(patterns.isEmpty ? "none detected" : patterns.joined(separator: ", ")),
                            "issueCount": .int(issueCount), "forceUnwrapCount": .int(forceUnwrapCount),
                            "todoCount": .int(todoCount), "issues": .string(issues.joined(separator: "\n")),
                            "suggestions": .string(suggestions.joined(separator: "\n"))],
                           summary: summary)
    }

    func agenticCodeIndex(_ call: MCPToolCall) throws -> MCPToolResult {
        let (raw, root, scope) = try agenticCodeResolveScope(call, key: "projectPath", missingMessage: "Missing projectPath")
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scope)
        let index = Self.agenticCodeBuildIndex(files: files, root: root)
        var summary = "Project code indexed successfully at \(raw): \(index.symbolCount) symbols across \(index.fileCount) files."
        summary += "\nClasses: \(index.classCount), structs: \(index.structCount), enums: \(index.enumCount), protocols: \(index.protocolCount), actors: \(index.actorCount), functions: \(index.functionCount)."
        if !index.symbolsText.isEmpty { summary += "\n" + index.symbolsText }
        return .structured(["fileCount": .int(index.fileCount), "symbolCount": .int(index.symbolCount),
                            "classCount": .int(index.classCount), "structCount": .int(index.structCount),
                            "enumCount": .int(index.enumCount), "protocolCount": .int(index.protocolCount),
                            "actorCount": .int(index.actorCount), "functionCount": .int(index.functionCount),
                            "symbols": .string(index.symbolsText)],
                           summary: summary)
    }

    func agenticCodeProjectIndexing(_ call: MCPToolCall) throws -> MCPToolResult {
        let (raw, root, scope) = try agenticCodeResolveScope(call, key: "root_path", missingMessage: "Missing root_path argument")
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scope)
        let index = Self.agenticCodeBuildIndex(files: files, root: root)
        var summary = "Project at \(raw) has been indexed. \(index.symbolCount) symbols found across \(index.fileCount) files."
        summary += "\nClasses: \(index.classCount), structs: \(index.structCount), enums: \(index.enumCount), protocols: \(index.protocolCount), actors: \(index.actorCount), functions: \(index.functionCount)."
        if !index.symbolsText.isEmpty { summary += "\n" + index.symbolsText }
        return .structured(["fileCount": .int(index.fileCount), "symbolCount": .int(index.symbolCount),
                            "classCount": .int(index.classCount), "structCount": .int(index.structCount),
                            "enumCount": .int(index.enumCount), "protocolCount": .int(index.protocolCount),
                            "actorCount": .int(index.actorCount), "functionCount": .int(index.functionCount),
                            "symbols": .string(index.symbolsText)],
                           summary: summary)
    }
}

extension YcodeMCPHost {
    // MARK: - Project audit, security scan, license scan

    func agenticCodeAuditProject(_ call: MCPToolCall) throws -> MCPToolResult {
        let (raw, root, scope) = try agenticCodeResolveScope(call, key: "projectPath", missingMessage: "Missing projectPath")
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scope)
        var totalLines = 0, testFileCount = 0, todoCount = 0, forceUnwrapCount = 0, secretFindingCount = 0
        for url in files {
            let rel = Self.staticAnalysisRelative(url, root: root)
            if rel.hasSuffix("Tests.swift") || rel.contains("/Tests/") { testFileCount += 1 }
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            let lines = text.components(separatedBy: "\n")
            totalLines += lines.count
            todoCount += Self.agenticCodeTodoCount(lines)
            forceUnwrapCount += Self.agenticCodeBugFindings(lines).filter { $0.kind.hasPrefix("force") }.count
            secretFindingCount += Self.agenticCodeSecretFindings(lines).count
        }
        let topEntries = (try? FileManager.default.contentsOfDirectory(atPath: scope.path)) ?? []
        let lowerEntries = topEntries.map { $0.lowercased() }
        let hasReadme = lowerEntries.contains { $0.hasPrefix("readme") }
        let hasLicense = lowerEntries.contains { $0.hasPrefix("license") || $0.hasPrefix("licence") || $0.hasPrefix("copying") }
        let hasBuildSystem = lowerEntries.contains("package.swift") || topEntries.contains { $0.hasSuffix(".xcodeproj") }
        let checks: [(name: String, passed: Bool, detail: String)] = [
            ("README present", hasReadme, hasReadme ? "A README file exists at the project root." : "No README file at the project root."),
            ("License file present", hasLicense, hasLicense ? "A license file exists at the project root." : "No license file at the project root."),
            ("Tests present", testFileCount > 0, testFileCount > 0 ? "\(testFileCount) test file(s) found." : "No test files found."),
            ("No TODO markers", todoCount == 0, todoCount == 0 ? "No TODO / FIXME / XXX / HACK markers." : "\(todoCount) marker(s) found."),
            ("No force unwraps", forceUnwrapCount == 0, forceUnwrapCount == 0 ? "No force-unwrap / force-try / force-cast sites." : "\(forceUnwrapCount) site(s) found."),
            ("No hardcoded secrets", secretFindingCount == 0, secretFindingCount == 0 ? "No hardcoded secrets or insecure endpoints." : "\(secretFindingCount) finding(s)."),
            ("Build system present", hasBuildSystem, hasBuildSystem ? "A Package.swift or .xcodeproj exists at the project root." : "No Package.swift or .xcodeproj at the project root."),
        ]
        let failureCount = checks.filter { !$0.passed }.count
        let checkText = checks.map { "\($0.passed ? "PASS" : "FAIL") — \($0.name): \($0.detail)" }.joined(separator: "\n")
        let summary = """
        Project audit for \(raw):
        - Swift files: \(files.count), total lines: \(totalLines), test files: \(testFileCount)
        - TODO markers: \(todoCount), force-unwrap sites: \(forceUnwrapCount), secret findings: \(secretFindingCount)
        - Checks: \(checks.count - failureCount) passed, \(failureCount) failed
        \(checkText)
        """
        return .structured(["swiftFileCount": .int(files.count), "totalLines": .int(totalLines),
                            "testFileCount": .int(testFileCount), "todoCount": .int(todoCount),
                            "forceUnwrapCount": .int(forceUnwrapCount), "secretFindingCount": .int(secretFindingCount),
                            "hasReadme": .bool(hasReadme), "hasLicense": .bool(hasLicense),
                            "checkCount": .int(checks.count), "failureCount": .int(failureCount),
                            "findings": .string(checkText)],
                           summary: summary)
    }

    func agenticCodeSecurityScan(_ call: MCPToolCall) throws -> MCPToolResult {
        let (raw, root, scope) = try agenticCodeResolveScope(call, key: "projectPath", missingMessage: "Missing projectPath")
        let all = Self.agenticCodeEnumerateAllFiles(at: scope)
        var scanned = 0
        var filesWithFindings: Set<String> = []
        var findings: [String] = []
        for url in all {
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            scanned += 1
            let rel = Self.staticAnalysisRelative(url, root: root)
            let found = Self.agenticCodeSecretFindings(text.components(separatedBy: "\n"))
            if !found.isEmpty { filesWithFindings.insert(rel) }
            for finding in found {
                findings.append("\(rel):\(finding.line) [\(finding.kind)]")
                if findings.count >= 200 { break }
            }
            if findings.count >= 200 { break }
        }
        let findingText = findings.joined(separator: "\n")
        if findings.isEmpty {
            return .structured(["findingCount": .int(0), "filesScanned": .int(scanned),
                                "filesWithFindings": .int(0), "findings": .string("")],
                               summary: "Security scan of \(raw): no hardcoded secrets or insecure endpoints found in \(scanned) file(s).")
        }
        return .structured(["findingCount": .int(findings.count), "filesScanned": .int(scanned),
                            "filesWithFindings": .int(filesWithFindings.count), "findings": .string(findingText)],
                           summary: "Security scan of \(raw): \(findings.count) finding(s) in \(filesWithFindings.count) file(s) (of \(scanned) scanned).\n" + findingText)
    }

    func agenticCodeLicenseScan(_ call: MCPToolCall) throws -> MCPToolResult {
        let (raw, root, scope) = try agenticCodeResolveScope(call, key: "projectPath", missingMessage: "Missing projectPath")
        let all = Self.agenticCodeEnumerateAllFiles(at: scope)
        let licenseStems: Set<String> = ["license", "licence", "copying", "notice", "unlicense"]
        let sourceExtensions: Set<String> = ["swift", "m", "h", "mm", "c", "cpp"]
        guard let spdxRegex = try? NSRegularExpression(pattern: "SPDX-License-Identifier:\\s*([A-Za-z0-9][A-Za-z0-9.\\-+]*)(?:\\s|$)", options: []) else {
            throw MCPToolError("License Scan: failed to build SPDX pattern.")
        }
        var licenseFiles: [String] = []
        var licenseTerms: [String] = []
        var spdx: [String: Int] = [:]
        var filesScanned = 0
        var resolvedURL: URL?
        for url in all {
            let rel = Self.staticAnalysisRelative(url, root: root)
            if url.lastPathComponent == "Package.resolved" && resolvedURL == nil { resolvedURL = url }
            if licenseStems.contains(url.deletingPathExtension().lastPathComponent.lowercased()) {
                licenseFiles.append(rel)
                if let text = Self.staticAnalysisReadText(url) {
                    licenseTerms.append("\(rel): \(Self.agenticCodeLicenseTerm(text))")
                }
            }
            guard sourceExtensions.contains(url.pathExtension.lowercased()),
                  let lines = Self.staticAnalysisReadLines(url) else { continue }
            filesScanned += 1
            for line in lines.prefix(15) {
                let range = NSRange(line.startIndex..., in: line)
                if let match = spdxRegex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 2, let idRange = Range(match.range(at: 1), in: line) {
                    spdx[String(line[idRange]), default: 0] += 1
                }
            }
        }
        var dependencies: [(name: String, version: String)] = []
        if let resolvedURL,
           let data = try? Data(contentsOf: resolvedURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pins = json["pins"] as? [[String: Any]] {
            for pin in pins {
                let name = (pin["identity"] as? String) ?? (pin["package"] as? String) ?? ""
                var version = (pin["version"] as? String) ?? ""
                if version.isEmpty, let state = pin["state"] as? [String: Any] {
                    version = state["version"] as? String ?? ""
                }
                if !name.isEmpty { dependencies.append((name: name, version: version)) }
            }
        }
        dependencies.sort { $0.name < $1.name }
        let spdxText = spdx.keys.sorted().map { "\($0) ×\(spdx[$0] ?? 0)" }.joined(separator: ", ")
        let dependencyText = dependencies.map { $0.version.isEmpty ? $0.name : "\($0.name) \($0.version)" }.joined(separator: "\n")
        var summaryLines = [
            "License scan of \(raw):",
            "- License files (\(licenseFiles.count)): \(licenseFiles.isEmpty ? "none found" : licenseFiles.joined(separator: ", "))",
        ]
        if !licenseTerms.isEmpty { summaryLines.append("- License terms: " + licenseTerms.joined(separator: "; ")) }
        summaryLines.append("- SPDX identifiers in source headers (\(spdx.count) distinct): \(spdxText.isEmpty ? "none found" : spdxText)")
        summaryLines.append("- Dependencies in Package.resolved (\(dependencies.count)): \(dependencies.isEmpty ? "no Package.resolved found" : "\n" + dependencyText)")
        summaryLines.append("- Dependency license terms are not determined by this scan; no SPDX database or network lookup is performed.")
        let summary = summaryLines.joined(separator: "\n")
        return .structured(["licenseFileCount": .int(licenseFiles.count),
                            "licenseFiles": .string(licenseFiles.joined(separator: "\n")),
                            "spdxCount": .int(spdx.count), "spdxIdentifiers": .string(spdxText),
                            "dependencyCount": .int(dependencies.count), "dependencies": .string(dependencyText),
                            "filesScanned": .int(filesScanned)],
                           summary: summary)
    }
}

extension YcodeMCPHost {
    // MARK: - Shared helpers (all prefixed `agenticCode`)

    /// A declared type or function: kind (`class` / `struct` /
    /// `enum` / `actor` / `protocol` / `func`), name, 1-based line.
    struct AgenticCodeDeclaration: Sendable {
        var kind: String
        var name: String
        var line: Int
    }

    /// One heuristic bug finding: 1-based line, kind, trimmed line.
    struct AgenticCodeBugFinding: Sendable {
        var line: Int
        var kind: String
        var text: String
    }

    /// One secret / insecure-endpoint finding: 1-based line and
    /// kind only — the matched value is never carried.
    struct AgenticCodeSecretFinding: Sendable {
        var line: Int
        var kind: String
    }

    /// The in-memory declaration index shared by `code_index` and
    /// `project_indexing`.
    struct AgenticCodeIndex: Sendable {
        var fileCount: Int
        var symbolCount: Int
        var classCount: Int
        var structCount: Int
        var enumCount: Int
        var protocolCount: Int
        var actorCount: Int
        var functionCount: Int
        var symbolsText: String
    }

    /// A required inline-code argument; a missing or blank value
    /// fails with Legacy's own message (e.g. "Missing code").
    /// The original (untrimmed) code is returned.
    nonisolated static func agenticCodeRequiredCode(_ call: MCPToolCall, missingMessage: String) throws -> String {
        guard let code = call.arguments["code"]?.string,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError(missingMessage)
        }
        return code
    }

    /// A required trimmed path argument; a missing or blank value
    /// fails with Legacy's own message.
    nonisolated static func agenticCodeRequiredPath(_ call: MCPToolCall, _ key: String, missingMessage: String) throws -> String {
        guard let raw = call.arguments[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError(missingMessage)
        }
        return raw
    }

    /// Resolves a project-scoped path argument: the session, the
    /// workspace root, and the strict scan scope. Any `..` fails
    /// with the static-analysis "Invalid path" message; a missing
    /// path fails with "Path not found: <raw>".
    func agenticCodeResolveScope(_ call: MCPToolCall, key: String, missingMessage: String) throws -> (raw: String, root: URL, scope: URL) {
        let s = try session(for: call)
        let raw = try Self.agenticCodeRequiredPath(call, key, missingMessage: missingMessage)
        let root = Self.folder(of: s.model)
        guard let scope = Self.staticAnalysisResolveScanPath(raw, in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        guard FileManager.default.fileExists(atPath: scope.path) else {
            throw MCPToolError("Path not found: \(raw)")
        }
        return (raw, root, scope)
    }

    /// Every file under a scope (file or directory): skips
    /// `.git` / `DerivedData` / `.build` / `build` / `Pods` /
    /// `node_modules` / `.swiftpm` / `.venv`, drops files over
    /// 300 KB, at most 5000 files, sorted by path. Hidden files
    /// are included (`.env` files are a common secret store).
    nonisolated static func agenticCodeEnumerateAllFiles(at root: URL) -> [URL] {
        let skippedDirs: Set<String> = [".git", "DerivedData", ".build", "build", "Pods", "node_modules", ".swiftpm", ".venv"]
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return staticAnalysisFileSize(root) <= 300_000 ? [root] : []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else {
            return results
        }
        while let url = enumerator.nextObject() as? URL {
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if skippedDirs.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            if staticAnalysisFileSize(url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Top-level declarations and `func` declarations per line:
    /// the type regex anchors at the trimmed line start (with an
    /// optional access / `final` modifier), mirroring Legacy's
    /// `extractDeclaredTypes`, plus `protocol`; function names use
    /// Legacy's `\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)` regex. Full-line
    /// comments are skipped; matches in strings still count.
    nonisolated static func agenticCodeScanDeclarations(_ lines: [String]) -> [AgenticCodeDeclaration] {
        guard let typeRegex = try? NSRegularExpression(
            pattern: "^(?:public |private |internal |fileprivate |open )?(?:final )?(class|struct|enum|actor|protocol)\\s+([A-Za-z0-9_]+)",
            options: []),
            let funcRegex = try? NSRegularExpression(pattern: "\\bfunc\\s+([A-Za-z_][A-Za-z0-9_]*)", options: []) else {
            return []
        }
        var out: [AgenticCodeDeclaration] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            let trimmedRange = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = typeRegex.firstMatch(in: trimmed, options: [], range: trimmedRange),
               match.numberOfRanges >= 3,
               let kindRange = Range(match.range(at: 1), in: trimmed),
               let nameRange = Range(match.range(at: 2), in: trimmed) {
                out.append(AgenticCodeDeclaration(kind: String(trimmed[kindRange]), name: String(trimmed[nameRange]), line: index + 1))
            }
            let lineRange = NSRange(line.startIndex..., in: line)
            for match in funcRegex.matches(in: line, options: [], range: lineRange) where match.numberOfRanges >= 2 {
                if let nameRange = Range(match.range(at: 1), in: line) {
                    out.append(AgenticCodeDeclaration(kind: "func", name: String(line[nameRange]), line: index + 1))
                }
            }
        }
        return out
    }

    /// Heuristic bug patterns in one file's (or one supplied code
    /// string's) lines. A `!` counts as a force unwrap only when
    /// it follows an identifier, `)`, `]` or `}`, is not part of
    /// `!=`, and is not followed by `"` (punctuation inside a
    /// string literal). Boolean negation (`!flag`) is not flagged.
    /// Full-line comments are skipped; matches inside strings
    /// otherwise still count.
    nonisolated static func agenticCodeBugFindings(_ lines: [String]) -> [AgenticCodeBugFinding] {
        guard let forceUnwrap = try? NSRegularExpression(pattern: "[A-Za-z0-9_\\]\\)\\}]!(?!=)(?!\\\")", options: []),
              let tryBang = try? NSRegularExpression(pattern: "\\btry!", options: []),
              let asBang = try? NSRegularExpression(pattern: "\\bas!", options: []),
              let fatal = try? NSRegularExpression(pattern: "\\b(fatalError|preconditionFailure)\\s*\\(", options: []),
              let singleLineCatch = try? NSRegularExpression(pattern: "\\bcatch\\s*\\{\\s*\\}", options: []) else {
            return []
        }
        var findings: [AgenticCodeBugFinding] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            let range = NSRange(line.startIndex..., in: line)
            // `try!` / `as!` first: their `!` would also match the
            // force-unwrap pattern (`y!` in `try!`), so the
            // force-unwrap check runs only when neither matched.
            if tryBang.firstMatch(in: line, options: [], range: range) != nil {
                findings.append(AgenticCodeBugFinding(line: index + 1, kind: "force try (try!)", text: trimmed))
            } else if asBang.firstMatch(in: line, options: [], range: range) != nil {
                findings.append(AgenticCodeBugFinding(line: index + 1, kind: "force cast (as!)", text: trimmed))
            } else if forceUnwrap.firstMatch(in: line, options: [], range: range) != nil {
                findings.append(AgenticCodeBugFinding(line: index + 1, kind: "force unwrap (!)", text: trimmed))
            }
            if fatal.firstMatch(in: line, options: [], range: range) != nil {
                findings.append(AgenticCodeBugFinding(line: index + 1, kind: "fatalError / preconditionFailure call", text: trimmed))
            }
            if singleLineCatch.firstMatch(in: line, options: [], range: range) != nil {
                findings.append(AgenticCodeBugFinding(line: index + 1, kind: "empty catch block", text: trimmed))
            }
            // Multi-line empty catch: a line opening a `catch`
            // block (`catch {`, `} catch {`, `} catch FooError {`)
            // whose next non-blank line is a lone `}`.
            if trimmed.contains("catch") && trimmed.hasSuffix("{") {
                var next = index + 1
                while next < lines.count && lines[next].trimmingCharacters(in: .whitespaces).isEmpty { next += 1 }
                if next < lines.count && lines[next].trimmingCharacters(in: .whitespaces) == "}" {
                    findings.append(AgenticCodeBugFinding(line: index + 1, kind: "empty catch block", text: trimmed))
                }
            }
        }
        return findings
    }

    /// Word-boundaried action-item markers (Legacy's `todo_scan`
    /// pattern).
    nonisolated static func agenticCodeTodoCount(_ lines: [String]) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "\\b(TODO|FIXME|XXX|HACK)\\b", options: []) else { return 0 }
        var count = 0
        for line in lines {
            count += regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line)).count
        }
        return count
    }

    /// Secret / insecure-endpoint patterns in one file's lines.
    /// A secret finding names only the key (`api key`,
    /// `password`, …) — the matched value is never returned.
    /// `http://localhost` and `http://127.0.0.1` are not findings.
    /// Full-line comments are skipped for `http://` (a commented
    /// URL is harmless) but not for secrets (a commented-out
    /// credential is still a leak).
    nonisolated static func agenticCodeSecretFindings(_ lines: [String]) -> [AgenticCodeSecretFinding] {
        guard let secret = try? NSRegularExpression(
            pattern: "(?i)\\b(password|passwd|api[_-]?key|apikey|secret|access[_-]?token|private[_-]?key)\\s*[:=]\\s*[\"'][^\"'\\n]{4,}[\"']",
            options: []),
            let http = try? NSRegularExpression(pattern: "http://[^\\s\"'<>]+", options: []) else {
            return []
        }
        var findings: [AgenticCodeSecretFinding] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isComment = trimmed.hasPrefix("//")
            let range = NSRange(line.startIndex..., in: line)
            if !isComment, let match = http.firstMatch(in: line, options: [], range: range),
               let urlRange = Range(match.range, in: line) {
                let url = String(line[urlRange])
                if !url.hasPrefix("http://localhost") && !url.hasPrefix("http://127.0.0.1") {
                    findings.append(AgenticCodeSecretFinding(line: index + 1, kind: "insecure http endpoint"))
                }
            }
            if let match = secret.firstMatch(in: line, options: [], range: range),
               match.numberOfRanges >= 2, let keyRange = Range(match.range(at: 1), in: line) {
                // `apiKey` / `API_KEY` / `api-key` all read as
                // "api key": split camel humps, then lowercase and
                // turn `_` / `-` into spaces.
                let rawKey = String(line[keyRange])
                var spaced = ""
                for (offset, character) in rawKey.enumerated() {
                    if character.isUppercase, offset > 0,
                       let previous = rawKey.dropFirst(offset - 1).first, previous.isLowercase {
                        spaced.append(" ")
                    }
                    spaced.append(character)
                }
                var key = spaced.lowercased().replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
                while key.contains("  ") { key = key.replacingOccurrences(of: "  ", with: " ") }
                findings.append(AgenticCodeSecretFinding(line: index + 1, kind: "hardcoded secret (\(key))"))
            }
        }
        return findings
    }

    /// Function spans by brace-depth tracking from each `func`
    /// declaration line (heuristic: braces in strings or comments
    /// shift spans, as in Legacy's `call_hierarchy` callee scan).
    /// A function whose body never closes runs to end of file.
    nonisolated static func agenticCodeFunctionSpans(_ lines: [String]) -> [(name: String, start: Int, length: Int)] {
        guard let funcRegex = try? NSRegularExpression(pattern: "\\bfunc\\s+([A-Za-z_][A-Za-z0-9_]*)", options: []) else { return [] }
        var spans: [(name: String, start: Int, length: Int)] = []
        var stack: [(name: String, start: Int, depthBefore: Int, seenOpen: Bool)] = []
        var depth = 0
        for (index, line) in lines.enumerated() {
            let lineNo = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("//") {
                let range = NSRange(line.startIndex..., in: line)
                if let match = funcRegex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 2, let nameRange = Range(match.range(at: 1), in: line) {
                    stack.append((name: String(line[nameRange]), start: lineNo, depthBefore: depth, seenOpen: false))
                }
            }
            let opens = line.filter { $0 == "{" }.count
            let closes = line.filter { $0 == "}" }.count
            if opens > 0 {
                for i in stack.indices { stack[i].seenOpen = true }
            }
            depth += opens - closes
            while let top = stack.last, top.seenOpen, depth <= top.depthBefore {
                spans.append((name: top.name, start: top.start, length: lineNo - top.start + 1))
                stack.removeLast()
            }
        }
        for top in stack where top.seenOpen {
            spans.append((name: top.name, start: top.start, length: lines.count - top.start + 1))
        }
        return spans
    }

    /// Builds the in-memory declaration index for a set of Swift
    /// files: per-kind counts plus a capped `Kind Name —
    /// rel:line` listing (at most 200 entries, scan order).
    nonisolated static func agenticCodeBuildIndex(files: [URL], root: URL) -> AgenticCodeIndex {
        var entries: [(kind: String, name: String, rel: String, line: Int)] = []
        for url in files {
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            let rel = Self.staticAnalysisRelative(url, root: root)
            for declaration in Self.agenticCodeScanDeclarations(text.components(separatedBy: "\n")) {
                entries.append((kind: declaration.kind, name: declaration.name, rel: rel, line: declaration.line))
            }
        }
        let capped = Array(entries.prefix(200))
        return AgenticCodeIndex(
            fileCount: files.count,
            symbolCount: entries.count,
            classCount: entries.filter { $0.kind == "class" }.count,
            structCount: entries.filter { $0.kind == "struct" }.count,
            enumCount: entries.filter { $0.kind == "enum" }.count,
            protocolCount: entries.filter { $0.kind == "protocol" }.count,
            actorCount: entries.filter { $0.kind == "actor" }.count,
            functionCount: entries.filter { $0.kind == "func" }.count,
            symbolsText: capped.map { "\($0.kind) \($0.name) — \($0.rel):\($0.line)" }.joined(separator: "\n"))
    }

    /// The license a license file's text appears to grant, from
    /// its well-known phrases; "unrecognised terms" otherwise.
    nonisolated static func agenticCodeLicenseTerm(_ text: String) -> String {
        if text.contains("Apache License") { return "Apache License" }
        if text.contains("MIT License") { return "MIT License" }
        if text.contains("GNU GENERAL PUBLIC LICENSE") { return "GNU General Public License" }
        if text.contains("GNU LESSER GENERAL PUBLIC LICENSE") { return "GNU Lesser General Public License" }
        if text.contains("Mozilla Public License") { return "Mozilla Public License" }
        if text.contains("BSD 3-Clause") || text.contains("Redistribution and use in source and binary forms") { return "BSD License" }
        if text.contains("The Unlicense") { return "The Unlicense" }
        return "unrecognised terms"
    }
}
