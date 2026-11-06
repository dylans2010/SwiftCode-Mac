import Foundation
import YcodeAssistant
import YcodeIDECore

/// The ported Legacy static-analysis tool family (Wave 6, slice B).
///
/// Behaviour source: Legacy's `AssistLintTool`,
/// `AssistSwiftFormatLintTool`, `AssistDeadCodeScanTool`,
/// `AssistDeadCodeEliminatorTool`, `AssistDuplicateCodeScanTool`,
/// `AssistUnusedImportsDetectorTool`, `AssistImportCleanupTool`,
/// `AssistForceUnwrapScanTool`, `AssistTodoScanTool`,
/// `AssistTodoFixmeScannerTool`, `AssistCommentDensityReportTool`,
/// `AssistCodeCommentExtractTool`, `AssistComplexityAnalysisTool`,
/// `AssistFunctionSizeReportTool`, `AssistCodeMetricsTool`,
/// `AssistStringLiteralAuditTool`,
/// `AssistDeprecationUsageScanTool`, `AssistSwiftASTInspectorTool`,
/// `AssistSwiftConcurrencyAnalyzerTool`, `AssistConcurrencyAuditTool`,
/// `AssistEntryPointsDiscoverTool` and `AssistMigrationTool` (Dylan's
/// own code, ported under MIT), as specified in
/// `specs/ide/assist-testing-static-analysis.md`. Shared scanning
/// lives in `YcodeTools+StaticAnalysisSupport.swift`.
///
/// Conventions, following Waves 1–3:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter Wave 1 adds to every tool. Legacy's
///   parameter-name aliases (`filePath` / `file_path` for `path`,
///   `min_lines` for `minLines`) are NOT supported: Ycode's argument
///   validation rejects unknown arguments before the handler runs.
///   The one exception is `dead_code_eliminator`, whose canonical
///   Legacy parameter really is `filePath` — that name is kept.
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers) the way Ycode's other tools do — Legacy's
///   string-only map is not reproduced. Tools whose Legacy result
///   carries no data return a plain text result instead.
/// * Path resolution follows Legacy's split. The scan tools with
///   Legacy's strict per-tool resolver (`dead_code_scan`,
///   `duplicate_code_scan`, `todo_scan`, `import_cleanup`,
///   `concurrency_audit`) use `staticAnalysisResolveScanPath`
///   (blank → workspace root; any `..` → the Legacy "Invalid path"
///   failure; a missing root scans as zero files). Single-file tools
///   use the session-aware `resolveFileReadingPath`, except
///   `code_comment_extract` and `swift_ast_inspector`, which use the
///   strict `resolveFileWritingPath` (Legacy's
///   `AssistWorkspacePaths.resolve` shape). No path is ever allowed
///   to escape the workspace.
/// * All tools are `readOnly: true, idempotent: true`, `writes:
///   false` — except `import_cleanup`, the one mutating tool
///   (`safeMutation`, `writes: true`), which gates through
///   `commit()` — one approval per changed file, in order, stopping
///   at the first refusal (the Wave 2 multi-file shape). There is no
///   Autopilot bypass. `MCPServer.run` already refuses `writes:
///   true` tools when the server is read-only.
/// * `dead_code_eliminator` never writes anything despite its name:
///   Legacy's `riskLevel` is `safeRead` and its handler only reports
///   unused private declarations. The port keeps that.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * No YcodeSyntax AST is used. Ycode's `YcodeSyntax` is a
///   tokenizer / block-structure library, not a Swift declaration
///   parser, and the `YcodeMCP` target does not depend on it — and
///   Legacy's own tools are regex / line scans everywhere except
///   `swift_ast_inspector`. The port therefore reproduces Legacy's
///   heuristics faithfully (including their known blind spots:
///   references in strings and comments count as mentions,
///   substring matching where Legacy does it, brace counting that
///   ignores strings and comments) and the spec says so plainly.
///   Nothing here claims full AST fidelity.
/// * `swift_ast_inspector` implements only Legacy's regex structural
///   fallback (type-declaration hierarchy). Legacy's primary path
///   runs `xcrun swiftc -dump-ast`; Ycode's MCP host has no Swift
///   toolchain and does not shell out to Apple's toolchain, so that
///   path is not ported. The tool still returns real structural
///   results, exactly as Legacy does when `swiftc` is unavailable.
/// * `deprecation_usage_scan` checks deprecated names in sorted
///   order; Legacy iterates an `NSMutableSet` (unordered), so its
///   usage listing order is nondeterministic. The findings are the
///   same set.
/// * `import_cleanup`'s per-file write goes through `commit()`
///   (atomic temp-file + rename) rather than Legacy's direct
///   `write(to:atomically:)`; a mid-batch write failure therefore
///   surfaces as a tool error after earlier files were already
///   committed, as in Legacy (which also returns failure after
///   writing earlier files).
///
/// Wiring: the coordinator adds `staticAnalysisTools` to
/// `installTools()` in `YcodeTools.swift` (this file must not edit
/// that file). The registry aliases `metrics` →
/// `code_metrics_analyzer`, `dead_code` → `dead_code_eliminator`,
/// `migration_advisor` → `swift_migration_advisor`, `ast_inspector`
/// → `swift_ast_inspector`, `concurrency_analyzer` →
/// `swift_concurrency_analyzer`, `swift_format` →
/// `swift_format_lint`, `todo_scanner` → `todo_fixme_scanner` and
/// `unused_imports` → `unused_imports_detector` belong in
/// `MCPServer.toolAliases` (also coordinator-owned); they were
/// verified against Legacy's `AssistToolRegistry` alias table.
extension YcodeMCPHost {
    var staticAnalysisTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("code_lint", "Lint Code",
                 "Runs a linter on the specified file or directory.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file path to lint. Default: \".\".")]),
                 output: Schema.output(["issues": Schema.str])) { h, call in
                try h.staticAnalysisLintCode(call)
            },
            tool("swift_format_lint", "Swift Format Linter",
                 "Lints Swift source files for code style, line length, indentation, and formatting violations.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to Swift file in workspace.")],
                                      required: ["path"])) { h, call in
                try h.staticAnalysisSwiftFormatLint(call)
            },
            tool("dead_code_scan", "Dead Code Scan",
                 "Heuristic scan for Swift declarations that appear to have no references outside their own declaration line. Excludes public/open API, @main entry points, overrides, and well-known lifecycle names. Findings are heuristic leads, not proof of dead code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a file or directory to scan. Defaults to the workspace root.")]),
                 output: Schema.output(["scannedFiles": Schema.int, "declarationCount": Schema.int,
                                        "candidateCount": Schema.int, "candidates": Schema.str])) { h, call in
                try h.staticAnalysisDeadCodeScan(call)
            },
            tool("dead_code_eliminator", "Dead Code Eliminator",
                 "Identifies unreferenced private functions, unused variables, and unreachable code structures in Swift files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "filePath": Schema.string("Workspace-relative path to a Swift file to inspect.")],
                                      required: ["filePath"])) { h, call in
                try h.staticAnalysisDeadCodeEliminator(call)
            },
            tool("duplicate_code_scan", "Duplicate Code Scan",
                 "Heuristic scan for duplicated blocks of Swift code. Lines are normalized (trimmed, blank lines and full-line comments and brace-only lines skipped) and compared with a sliding window. Findings are heuristic leads — duplicated blocks may be intentional.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a file or directory to scan. Defaults to the workspace root."),
                                       "minLines": Schema.string("Minimum normalized lines per block, as a decimal string. Clamped to at least 3. Default: \"6\".")]),
                 output: Schema.output(["scannedFiles": Schema.int, "duplicateGroups": Schema.int, "groups": Schema.str])) { h, call in
                try h.staticAnalysisDuplicateCodeScan(call)
            },
            tool("unused_imports_detector", "Unused Imports Detector",
                 "Scans Swift files to detect redundant or unused framework imports.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to the Swift file.")],
                                      required: ["path"])) { h, call in
                try h.staticAnalysisUnusedImportsDetector(call)
            },
            tool("import_cleanup", "Import Cleanup",
                 "Removes unused import lines from Swift files. An import is removed only when its module name never appears as a whole word anywhere else in the file. Well-known Apple SDK and test modules (Foundation, SwiftUI, XCTest, Testing, and others) are never removed, because their symbols do not mention the module name. Only files that change are rewritten. Heuristic: it does not resolve re-exports or typealiases across modules.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a Swift file or directory to clean. Required.")],
                                      required: ["path"]),
                 output: Schema.output(["filesChanged": Schema.str, "removedImports": Schema.int,
                                        "changedFileCount": Schema.int, "removed": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.staticAnalysisImportCleanup(call)
            },
            tool("force_unwrap_scan", "Force Unwrap Scan",
                 "Scans Swift sources for force unwraps (!), try!, and as! — crash-prone constructs worth reviewing.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum findings. Default 100, max 1000.")]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.staticAnalysisForceUnwrapScan(call)
            },
            tool("todo_scan", "TODO Scan",
                 "Scans Swift source files for TODO, FIXME, XXX, and HACK markers and returns a file:line:text list with counts per tag.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a file or directory to scan. Defaults to the workspace root.")]),
                 output: Schema.output(["scannedFiles": Schema.int, "totalMarkers": Schema.int, "todo": Schema.int,
                                        "fixme": Schema.int, "xxx": Schema.int, "hack": Schema.int, "findings": Schema.str])) { h, call in
                try h.staticAnalysisTodoScan(call)
            },
            tool("todo_fixme_scanner", "TODO & FIXME Scanner",
                 "Scans workspace files to index all TODO, FIXME, MARK, HACK, and BUG annotations.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "tag": Schema.string("Optional specific tag filter: 'TODO', 'FIXME', 'BUG', 'HACK', or 'MARK'."),
                                       "maxResults": Schema.integer("Maximum number of results to return (default: 50).")])) { h, call in
                try h.staticAnalysisTodoFixmeScanner(call)
            },
            tool("comment_density_report", "Comment Density Report",
                 "Reports comment-to-code ratios per Swift file, flagging the least-documented files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum files to report. Default 30.")]),
                 output: Schema.output(["fileCount": Schema.int])) { h, call in
                try h.staticAnalysisCommentDensityReport(call)
            },
            tool("code_comment_extract", "Code Comment Extract",
                 "Extracts documentation comments (/// and /** */) for a symbol or a whole file, with locations.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative Swift file to extract from."),
                                       "symbol": Schema.string("Optional: only extract comments attached to this symbol name.")],
                                      required: ["path"]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.staticAnalysisCodeCommentExtract(call)
            },
            tool("complexity_analysis", "Complexity Analysis",
                 "Analyzes the cyclomatic complexity of code.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of the file to analyze.")],
                                      required: ["path"]),
                 output: Schema.output(["score": Schema.int, "rating": Schema.str])) { h, call in
                try h.staticAnalysisComplexityAnalysis(call)
            },
            tool("function_size_report", "Function Size Report",
                 "Finds the longest functions by line count, highlighting decomposition candidates.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "threshold": Schema.integer("Only report functions at or above this many lines. Default 60."),
                                       "limit": Schema.integer("Maximum functions to report. Default 30.")]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.staticAnalysisFunctionSizeReport(call)
            },
            tool("code_metrics_analyzer", "Code Metrics Analyzer",
                 "Calculates lines of code, comment density, type counts, and complexity metrics for Swift source files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to a Swift file or directory.")],
                                      required: ["path"])) { h, call in
                try h.staticAnalysisCodeMetricsAnalyzer(call)
            },
            tool("string_literal_audit", "String Literal Audit",
                 "Finds hardcoded user-facing string literals that are not routed through localization (NSLocalizedString / String(localized:)).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum findings. Default 100, max 1000.")]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.staticAnalysisStringLiteralAudit(call)
            },
            tool("deprecation_usage_scan", "Deprecation Usage Scan",
                 "Finds declarations marked @available(*, deprecated) in workspace Swift sources and reports where those deprecated symbols are used.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "limit": Schema.integer("Maximum usage sites. Default 100, max 500.")]),
                 output: Schema.output(["declarationCount": Schema.int, "usageCount": Schema.int])) { h, call in
                try h.staticAnalysisDeprecationUsageScan(call)
            },
            tool("swift_ast_inspector", "Swift AST Inspector",
                 "Inspects the abstract syntax tree (AST) and type declaration hierarchy of a Swift source file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to the Swift file within the workspace."),
                                       "symbol": Schema.string("Optional symbol name to filter AST declarations for.")],
                                      required: ["path"])) { h, call in
                try h.staticAnalysisSwiftASTInspector(call)
            },
            tool("swift_concurrency_analyzer", "Swift Concurrency Analyzer",
                 "Audits Swift code for Swift 6 strict concurrency hazards, mutable globals, and actor isolation boundaries.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Relative path to file or directory in workspace.")],
                                      required: ["path"])) { h, call in
                try h.staticAnalysisSwiftConcurrencyAnalyzer(call)
            },
            tool("concurrency_audit", "Concurrency Audit",
                 "Heuristic scan for Swift concurrency hazards: DispatchQueue.main.sync, nonisolated(unsafe), mutable static vars, Task blocks without await, force unwraps inside async functions, and SwiftUI types without @MainActor. All findings are heuristic leads, not confirmed bugs.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path of a file or directory to audit. Defaults to the workspace root.")]),
                 output: Schema.output(["scannedFiles": Schema.int, "findingCount": Schema.int, "findings": Schema.str])) { h, call in
                try h.staticAnalysisConcurrencyAudit(call)
            },
            tool("entry_points_discover", "Discover Entry Points",
                 "Finds application entry points: @main types, main.swift, and AppDelegate/SceneDelegate classes.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.staticAnalysisEntryPointsDiscover(call)
            },
            tool("swift_migration_advisor", "Swift 6 Migration Advisor",
                 "Audits Swift code for Swift 6 strict concurrency compliance, mutable globals, actor boundaries, and Sendable conformance.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to a Swift file or directory.")],
                                      required: ["path"])) { h, call in
                try h.staticAnalysisSwiftMigrationAdvisor(call)
            },
        ]
    }
}

extension YcodeMCPHost {
    // MARK: - Lint and dead code

    func staticAnalysisLintCode(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = call.arguments["path"]?.string ?? "."
        let url = try resolveFileReadingPath(path, in: s)
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to lint \(path): \(error.localizedDescription)")
        }
        let lines = content.components(separatedBy: .newlines)
        var issues: [String] = []
        for (index, line) in lines.enumerated() {
            if line.count > 120 {
                issues.append("Line \(index + 1) is too long (\(line.count) chars)")
            }
            if line.contains("TODO") || line.contains("FIXME") {
                issues.append("Line \(index + 1) contains a marker: \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        if issues.isEmpty {
            return .text("No basic linting issues found in \(path)")
        }
        return .structured(["issues": .string(issues.joined(separator: "\n"))],
                           summary: "Basic linting found \(issues.count) issues in \(path)")
    }

    func staticAnalysisSwiftFormatLint(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(path, in: s)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MCPToolError("File not found at path: \(path)")
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPToolError("Unable to read content of \(path)")
        }
        var issues: [String] = []
        let lines = content.components(separatedBy: .newlines)
        var consecutiveEmptyLines = 0
        for (i, line) in lines.enumerated() {
            let lineNum = i + 1
            if line.count > 140 {
                issues.append("Line \(lineNum): Line exceeds 140 characters (\(line.count) chars).")
            }
            if line.hasSuffix(" ") || line.hasSuffix("\t") {
                issues.append("Line \(lineNum): Trailing whitespace detected.")
            }
            if line.hasPrefix("\t") {
                issues.append("Line \(lineNum): Hard tab indentation used instead of spaces.")
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(";") && !trimmed.contains("/*") {
                issues.append("Line \(lineNum): Redundant trailing semicolon.")
            }
            if trimmed.isEmpty {
                consecutiveEmptyLines += 1
                if consecutiveEmptyLines > 2 {
                    issues.append("Line \(lineNum): More than two consecutive blank lines.")
                }
            } else {
                consecutiveEmptyLines = 0
            }
        }
        if issues.isEmpty {
            return .text("Formatting check passed! No style or whitespace issues found in `\(path)`.")
        }
        let summary = "### Swift Formatting Violations in `\(path)` (\(issues.count) issues):\n\n" +
            issues.prefix(30).map { "- \($0)" }.joined(separator: "\n")
        return .text(summary)
    }

    func staticAnalysisDeadCodeScan(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let scanRoot = Self.staticAnalysisResolveScanPath(call.arguments["path"]?.string, in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scanRoot)
        if files.isEmpty {
            return .structured(["scannedFiles": .int(0), "declarationCount": .int(0), "candidateCount": .int(0), "candidates": .string("")],
                               summary: "Dead Code Scan: no Swift files found.")
        }
        var entries: [(relative: String, lines: [String], text: String)] = []
        for url in files {
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            entries.append((relative: Self.staticAnalysisRelative(url, root: root), lines: text.components(separatedBy: "\n"), text: text))
        }
        var wordCounts: [String: Int] = [:]
        let separators = CharacterSet.alphanumerics.inverted
        for entry in entries {
            for word in entry.text.components(separatedBy: separators) where !word.isEmpty {
                wordCounts[word, default: 0] += 1
            }
        }
        guard let declRegex = try? NSRegularExpression(pattern: "\\b(?:func|class|struct|enum|protocol|let|var|typealias|actor)\\s+([A-Za-z_][A-Za-z0-9_]*)", options: []),
              let exclusionRegex = try? NSRegularExpression(pattern: "\\b(public|open|override)\\b|@main|@IBAction|@objc|PreviewProvider", options: []) else {
            throw MCPToolError("Dead Code Scan: failed to build declaration pattern.")
        }
        let excludedNames: Set<String> = ["main", "App", "init", "deinit", "body", "preview"]
        var candidates: [(relative: String, line: Int, kind: String, name: String, count: Int)] = []
        var declarationCount = 0
        for entry in entries {
            for (index, line) in entry.lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in declRegex.matches(in: line, options: [], range: range) {
                    guard match.numberOfRanges >= 2, let nameRange = Range(match.range(at: 1), in: line),
                          let fullRange = Range(match.range, in: line) else { continue }
                    let name = String(line[nameRange])
                    let kind = String(line[fullRange]).components(separatedBy: .whitespaces).first ?? "decl"
                    declarationCount += 1
                    if excludedNames.contains(name) { continue }
                    if exclusionRegex.firstMatch(in: line, options: [], range: range) != nil { continue }
                    let references = wordCounts[name] ?? 0
                    // The declaration line itself contributes one mention.
                    // A total of 1 means nothing else in the scanned
                    // corpus mentions it.
                    if references <= 1 {
                        candidates.append((relative: entry.relative, line: index + 1, kind: kind, name: name, count: references))
                    }
                }
            }
        }
        let capped = Array(candidates.prefix(200))
        var output = "Dead Code Scan (heuristic): scanned \(entries.count) Swift file(s), found \(declarationCount) declaration(s), \(candidates.count) candidate(s) with no other whole-word references.\n"
        output += "Names declared more than once (for example overloads) are not flagged, and references in strings or comments still count as mentions.\n"
        if capped.isEmpty {
            output += "No dead-code candidates found."
        } else {
            for candidate in capped {
                output += "- \(candidate.relative):\(candidate.line) \(candidate.kind) \(candidate.name) (corpus mentions: \(candidate.count))\n"
            }
            if candidates.count > capped.count {
                output += "… and \(candidates.count - capped.count) more candidate(s) omitted from this listing.\n"
            }
        }
        let candidateText = capped.map { "\($0.relative):\($0.line) \($0.kind) \($0.name)" }.joined(separator: "\n")
        return .structured(["scannedFiles": .int(entries.count), "declarationCount": .int(declarationCount),
                            "candidateCount": .int(candidates.count), "candidates": .string(candidateText)],
                           summary: output)
    }

    /// Despite the name, this tool never writes: Legacy's risk is
    /// `safeRead` and the handler only reports unused private
    /// declarations in one file.
    func staticAnalysisDeadCodeEliminator(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let filePath = try fileReadingRequiredString(call, "filePath")
        let targetURL = try resolveFileReadingPath(filePath, in: s)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw MCPToolError("File does not exist: \(filePath)")
        }
        guard let content = try? String(contentsOf: targetURL, encoding: .utf8) else {
            throw MCPToolError("Cannot read file: \(filePath)")
        }
        let lines = content.components(separatedBy: .newlines)
        var privateDeclarations: [(name: String, line: Int, kind: String)] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("//") { continue }
            if trimmed.contains("private func ") {
                let parts = trimmed.components(separatedBy: "private func ")
                if parts.count > 1 {
                    let fnPart = parts[1].components(separatedBy: "(")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fnPart.isEmpty {
                        privateDeclarations.append((name: fnPart, line: idx + 1, kind: "function"))
                    }
                }
            } else if trimmed.contains("fileprivate func ") {
                let parts = trimmed.components(separatedBy: "fileprivate func ")
                if parts.count > 1 {
                    let fnPart = parts[1].components(separatedBy: "(")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !fnPart.isEmpty {
                        privateDeclarations.append((name: fnPart, line: idx + 1, kind: "function"))
                    }
                }
            }
        }
        var deadDeclarations: [String] = []
        for decl in privateDeclarations {
            // Substring occurrences in the whole file (Legacy counts
            // substrings, not whole words): 1 means declared and never
            // called.
            let occurrences = content.components(separatedBy: decl.name).count - 1
            if occurrences <= 1 {
                deadDeclarations.append("Line \(decl.line): Unused private \(decl.kind) '\(decl.name)()' (0 calls in file).")
            }
        }
        if deadDeclarations.isEmpty {
            return .text("Dead Code Scan completed for \(filePath): All \(privateDeclarations.count) private declarations have active call sites.")
        }
        return .text("Dead Code Scan found \(deadDeclarations.count) unused declarations in \(filePath):\n" + deadDeclarations.joined(separator: "\n"))
    }

    func staticAnalysisDuplicateCodeScan(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let scanRoot = Self.staticAnalysisResolveScanPath(call.arguments["path"]?.string, in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        var minLines = Self.staticAnalysisInt(call.arguments["minLines"], default: 6)
        if minLines < 3 { minLines = 3 }
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scanRoot)
        if files.isEmpty {
            return .structured(["scannedFiles": .int(0), "duplicateGroups": .int(0), "groups": .string("")],
                               summary: "Duplicate Code Scan: no Swift files found.")
        }
        var windows: [String: [(file: String, line: Int)]] = [:]
        for url in files {
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            let relative = Self.staticAnalysisRelative(url, root: root)
            let normalized = Self.staticAnalysisNormalizedLines(text)
            guard normalized.count >= minLines else { continue }
            for start in 0...(normalized.count - minLines) {
                let key = normalized[start..<(start + minLines)].map { $0.text }.joined(separator: "\n")
                windows[key, default: []].append((file: relative, line: normalized[start].line))
            }
        }
        var groups: [(key: String, locations: [(file: String, line: Int)])] = []
        for (key, locations) in windows where locations.count >= 2 {
            groups.append((key: key, locations: locations))
        }
        groups.sort {
            let aMin = $0.locations.map { $0.line }.min() ?? 0
            let bMin = $1.locations.map { $0.line }.min() ?? 0
            if aMin != bMin { return aMin < bMin }
            return $0.locations.count > $1.locations.count
        }
        // Drop windows that are a shifted continuation of an
        // already-kept group: every location shifted by the same
        // positive offset.
        var kept: [(key: String, locations: [(file: String, line: Int)])] = []
        for group in groups {
            var isContinuation = false
            for existing in kept where existing.locations.count == group.locations.count {
                var shift: Int?
                var matches = true
                for (index, location) in group.locations.enumerated() {
                    let other = existing.locations[index]
                    if other.file != location.file { matches = false; break }
                    let delta = location.line - other.line
                    if delta <= 0 { matches = false; break }
                    if let current = shift, current != delta { matches = false; break }
                    shift = delta
                }
                if matches { isContinuation = true; break }
            }
            if !isContinuation {
                kept.append(group)
            }
            if kept.count >= 100 { break }
        }
        var output = "Duplicate Code Scan (heuristic): scanned \(files.count) Swift file(s) with window size \(minLines) normalized line(s), found \(kept.count) duplicated block group(s).\n"
        var groupText = ""
        if kept.isEmpty {
            output += "No duplicated blocks found."
        } else {
            for group in kept {
                let header = "Duplicate block ×\(group.locations.count):"
                output += "\(header)\n"
                groupText += "\(header)\n"
                for location in group.locations {
                    output += "  - \(location.file):\(location.line)\n"
                    groupText += "  - \(location.file):\(location.line)\n"
                }
                let snippet = group.key.components(separatedBy: "\n").prefix(3).map { "    \($0)" }.joined(separator: "\n")
                output += "\(snippet)\n"
                groupText += "\(snippet)\n"
            }
        }
        return .structured(["scannedFiles": .int(files.count), "duplicateGroups": .int(kept.count), "groups": .string(groupText)],
                           summary: output)
    }

    /// Legacy's normalization: trim, skip blank lines, full-line
    /// comments, and lines made only of punctuation.
    nonisolated static func staticAnalysisNormalizedLines(_ text: String) -> [(line: Int, text: String)] {
        let punctuation = Set<Character>(["{", "}", "(", ")", "[", "]", ",", ";", ":", "."])
        var result: [(line: Int, text: String)] = []
        for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("//") { continue }
            if trimmed.allSatisfy({ punctuation.contains($0) }) { continue }
            result.append((line: index + 1, text: trimmed))
        }
        return result
    }

    func staticAnalysisUnusedImportsDetector(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try fileReadingRequiredString(call, "path")
        let fileURL = try resolveFileReadingPath(path, in: s)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("File not found at path: \(path)")
        }
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            throw MCPToolError("Unable to read content of \(path)")
        }
        let lines = content.components(separatedBy: .newlines)
        var importedModules: [(line: Int, module: String)] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("import ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    let mod = parts[1].replacingOccurrences(of: ";", with: "")
                    importedModules.append((line: i + 1, module: mod))
                }
            }
        }
        if importedModules.isEmpty {
            return .text("No framework imports found in `\(path)`.")
        }
        let bodyContent = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }.joined(separator: "\n")
        var unusedCandidates: [String] = []
        for item in importedModules {
            let mod = item.module
            if bodyContent.contains(mod + ".") { continue }
            if let symbols = Self.staticAnalysisFrameworkSymbols[mod] {
                let foundSymbol = symbols.contains { bodyContent.contains($0) }
                if !foundSymbol {
                    unusedCandidates.append("Line \(item.line): `import \(mod)` — no known \(mod) symbols or explicit references found.")
                }
            }
        }
        if unusedCandidates.isEmpty {
            return .text("Import analysis clean: All imported modules appears to be referenced in `\(path)`.")
        }
        return .text("### Potentially Unused Imports in `\(path)`:\n\n" + unusedCandidates.map { "- \($0)" }.joined(separator: "\n"))
    }

    func staticAnalysisImportCleanup(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let rawPath = call.arguments["path"]?.string, !rawPath.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        guard let scanRoot = Self.staticAnalysisResolveScanPath(rawPath, in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scanRoot)
        if files.isEmpty {
            return .structured(["filesChanged": .string(""), "removedImports": .int(0), "changedFileCount": .int(0)],
                               summary: "Import Cleanup: no Swift files found.")
        }
        guard let importRegex = try? NSRegularExpression(pattern: "^\\s*(?:@testable\\s+)?import\\s+([A-Za-z_][A-Za-z0-9_]*)\\b", options: []) else {
            throw MCPToolError("Import Cleanup: failed to build import pattern.")
        }
        var changed: [String] = []
        var removed: [String] = []
        for url in files {
            guard let content = Self.staticAnalysisReadText(url) else { continue }
            let relative = Self.staticAnalysisRelative(url, root: root)
            let lines = content.components(separatedBy: "\n")
            var importLineIndexes: [Int] = []
            var importModules: [Int: String] = [:]
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if let match = importRegex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 2, let moduleRange = Range(match.range(at: 1), in: line) {
                    importLineIndexes.append(index)
                    importModules[index] = String(line[moduleRange])
                }
            }
            if importLineIndexes.isEmpty { continue }
            let bodyText = lines.enumerated().filter { !importLineIndexes.contains($0.offset) }.map { $0.element }.joined(separator: "\n")
            var removeIndexes: Set<Int> = []
            for index in importLineIndexes {
                guard let module = importModules[index] else { continue }
                if Self.staticAnalysisProtectedModules.contains(module) { continue }
                let usagePattern = "\\b" + NSRegularExpression.escapedPattern(for: module) + "\\b"
                guard let usageRegex = try? NSRegularExpression(pattern: usagePattern, options: []) else { continue }
                let bodyRange = NSRange(bodyText.startIndex..., in: bodyText)
                if usageRegex.firstMatch(in: bodyText, options: [], range: bodyRange) == nil {
                    removeIndexes.insert(index)
                    removed.append("\(relative): import \(module)")
                }
            }
            if removeIndexes.isEmpty { continue }
            let updated = lines.enumerated().filter { !removeIndexes.contains($0.offset) }.map { $0.element }.joined(separator: "\n")
            // One approval per changed file, in order; the first
            // refusal stops the batch (files already committed stay
            // changed, as in Legacy, which writes files as it goes).
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: relative, original: content, proposed: updated,
                                       summary: "Remove unused imports in \(relative)"), call: call, session: s)
            changed.append(relative)
        }
        if changed.isEmpty {
            return .structured(["filesChanged": .string(""), "removedImports": .int(0), "changedFileCount": .int(0)],
                               summary: "Import Cleanup: no unused imports found in \(files.count) Swift file(s). Nothing changed.")
        }
        return .structured(["filesChanged": .string(changed.joined(separator: "\n")), "removedImports": .int(removed.count),
                            "changedFileCount": .int(changed.count), "removed": .string(removed.joined(separator: "\n"))],
                           summary: "Import Cleanup: removed \(removed.count) unused import(s) across \(changed.count) file(s):\n" + removed.map { "- \($0)" }.joined(separator: "\n"))
    }
}

extension YcodeMCPHost {
    // MARK: - Workspace-wide scans

    func staticAnalysisForceUnwrapScan(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let limit = max(1, min(1000, call.int("limit") ?? 100))
        let patterns: [(NSRegularExpression?, String)] = [
            (try? NSRegularExpression(pattern: "(?<![=!])!(?!=)"), "force unwrap (!)"),
            (try? NSRegularExpression(pattern: "\\btry!\\b"), "try!"),
            (try? NSRegularExpression(pattern: "\\bas! "), "as!"),
        ]
        var findings: [(String, String)] = []
        for url in Self.staticAnalysisSwiftFiles(under: root) {
            guard let lines = Self.staticAnalysisReadLines(url) else { continue }
            let rel = Self.staticAnalysisRelative(url, root: root)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                for (pattern, label) in patterns {
                    guard let p = pattern else { continue }
                    if p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        if label == "force unwrap (!)" && t.contains("@IBOutlet") { continue }
                        findings.append(("\(rel):\(i + 1)", label))
                        break
                    }
                }
                if findings.count >= limit { break }
            }
            if findings.count >= limit { break }
        }
        if findings.isEmpty {
            return .structured(["count": .int(0)], summary: "No force-unwrap constructs found.")
        }
        var lines = ["Force-unwrap constructs (\(findings.count)\(findings.count >= limit ? "+" : "")):"]
        lines += findings.map { "- \($0.0) [\($0.1)]" }
        return .structured(["count": .int(findings.count)], summary: lines.joined(separator: "\n"))
    }

    func staticAnalysisTodoScan(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let scanRoot = Self.staticAnalysisResolveScanPath(call.arguments["path"]?.string, in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scanRoot)
        if files.isEmpty {
            return .structured(["scannedFiles": .int(0), "totalMarkers": .int(0), "todo": .int(0), "fixme": .int(0),
                                "xxx": .int(0), "hack": .int(0), "findings": .string("")],
                               summary: "TODO Scan: no Swift files found.")
        }
        guard let tagRegex = try? NSRegularExpression(pattern: "\\b(TODO|FIXME|XXX|HACK)\\b[\\s:]*([^\\n]*)", options: []) else {
            throw MCPToolError("TODO Scan: failed to build marker pattern.")
        }
        var counts: [String: Int] = ["TODO": 0, "FIXME": 0, "XXX": 0, "HACK": 0]
        var findings: [String] = []
        for url in files {
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            let relative = Self.staticAnalysisRelative(url, root: root)
            let lines = text.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                for match in tagRegex.matches(in: line, options: [], range: range) {
                    guard match.numberOfRanges >= 3,
                          let tagRange = Range(match.range(at: 1), in: line),
                          let textRange = Range(match.range(at: 2), in: line) else { continue }
                    let tag = String(line[tagRange])
                    let markerText = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                    counts[tag, default: 0] += 1
                    findings.append("\(relative):\(index + 1) \(tag): \(markerText)")
                    if findings.count >= 1000 { break }
                }
                if findings.count >= 1000 { break }
            }
            if findings.count >= 1000 { break }
        }
        let total = counts.values.reduce(0, +)
        var output = "TODO Scan: scanned \(files.count) Swift file(s), found \(total) marker(s) — TODO: \(counts["TODO"] ?? 0), FIXME: \(counts["FIXME"] ?? 0), XXX: \(counts["XXX"] ?? 0), HACK: \(counts["HACK"] ?? 0).\n"
        if findings.isEmpty {
            output += "No TODO/FIXME/XXX/HACK markers found."
        } else {
            output += findings.joined(separator: "\n")
            if total > findings.count {
                output += "\n… and \(total - findings.count) more marker(s) omitted (listing capped at 1000)."
            }
        }
        return .structured(["scannedFiles": .int(files.count), "totalMarkers": .int(total), "todo": .int(counts["TODO"] ?? 0),
                            "fixme": .int(counts["FIXME"] ?? 0), "xxx": .int(counts["XXX"] ?? 0), "hack": .int(counts["HACK"] ?? 0),
                            "findings": .string(findings.joined(separator: "\n"))],
                           summary: output)
    }

    func staticAnalysisTodoFixmeScanner(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let tagFilter = call.arguments["tag"]?.string
        let maxResults = call.int("maxResults") ?? 50
        var results: [(tag: String, file: String, line: Int, text: String)] = []
        let targets = ["TODO:", "FIXME:", "BUG:", "HACK:", "MARK:"]
        let activeTags = tagFilter != nil ? ["\(tagFilter!.uppercased()):"] : targets
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" || fileURL.pathExtension == "m" || fileURL.pathExtension == "h" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = text.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                for t in activeTags {
                    if let range = line.range(of: t) {
                        let snippet = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                        results.append((tag: t.replacingOccurrences(of: ":", with: ""), file: relPath, line: idx + 1, text: snippet))
                        if results.count >= maxResults { break }
                    }
                }
                if results.count >= maxResults { break }
            }
            if results.count >= maxResults { break }
        }
        if results.isEmpty {
            return .text("No TODO/FIXME/BUG annotations found in workspace.")
        }
        var report = "### Workspace Action Items (\(results.count) found):\n\n"
        let grouped = Dictionary(grouping: results, by: { $0.tag })
        for tag in grouped.keys.sorted() {
            report += "#### \(tag) (\(grouped[tag]!.count)):\n"
            for item in grouped[tag]! {
                report += "- `\(item.file):\(item.line)` → \(item.text)\n"
            }
            report += "\n"
        }
        return .text(report)
    }

    func staticAnalysisCommentDensityReport(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let limit = max(1, min(500, call.int("limit") ?? 30))
        var rows: [(String, Double, Int, Int)] = []
        for url in Self.staticAnalysisSwiftFiles(under: root) {
            guard let lines = Self.staticAnalysisReadLines(url) else { continue }
            var comment = 0, code = 0
            var inBlock = false
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                if inBlock {
                    comment += 1
                    if t.contains("*/") { inBlock = false }
                    continue
                }
                if t.hasPrefix("//") { comment += 1 }
                else if t.hasPrefix("/*") {
                    comment += 1
                    if !t.contains("*/") { inBlock = true }
                }
                else { code += 1 }
            }
            let total = comment + code
            guard total > 0 else { continue }
            rows.append((Self.staticAnalysisRelative(url, root: root), Double(comment) / Double(total), comment, code))
        }
        rows.sort { $0.1 < $1.1 }
        var lines = ["Comment density (lowest first, \(rows.count) files):"]
        for (path, ratio, comment, code) in rows.prefix(limit) {
            lines.append(String(format: "- %.1f%% — %@ (%d comment / %d code lines)", ratio * 100, path, comment, code))
        }
        return .structured(["fileCount": .int(rows.count)], summary: lines.joined(separator: "\n"))
    }

    func staticAnalysisCodeCommentExtract(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let symbol = call.arguments["symbol"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = resolveFileWritingPath(raw, in: s),
              let lines = Self.staticAnalysisReadLines(url) else {
            throw MCPToolError("Cannot read file at: \(raw)")
        }
        var results: [(String, String)] = []
        var pending: [String] = []
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("///") {
                pending.append(String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces))
                continue
            }
            if t.hasPrefix("/**") {
                var block = String(t.dropFirst(3))
                if let end = block.range(of: "*/") { block = String(block[..<end.lowerBound]) }
                pending.append(block.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "* ")))
                continue
            }
            if !pending.isEmpty {
                let doc = pending.joined(separator: "\n")
                pending.removeAll()
                if t.isEmpty || t.hasPrefix("//") || t.hasPrefix("@") { continue }
                let name = String(t.prefix(100))
                if let symbol, !symbol.isEmpty, !name.contains(symbol) { continue }
                results.append(("\(raw):\(i + 1)", doc + "\n→ " + name))
            } else if !t.isEmpty && !t.hasPrefix("//") {
                pending.removeAll()
            }
        }
        if results.isEmpty {
            return .structured(["count": .int(0)],
                               summary: "No documentation comments found in \(raw)\(symbol.map { " for '\($0)'" } ?? "").")
        }
        var out = ["Documentation comments in \(raw) (\(results.count)):"]
        for (loc, doc) in results.prefix(50) {
            out.append("- \(loc):\n  \(doc.replacingOccurrences(of: "\n", with: "\n  "))")
        }
        return .structured(["count": .int(results.count)], summary: out.joined(separator: "\n"))
    }

    func staticAnalysisComplexityAnalysis(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try fileReadingRequiredString(call, "path")
        let url = try resolveFileReadingPath(path, in: s)
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to analyze complexity for \(path): \(error.localizedDescription)")
        }
        let controlFlowKeywords = ["if ", "for ", "while ", "switch ", "case ", "guard ", "catch "]
        var complexity = 1
        for keyword in controlFlowKeywords {
            complexity += content.components(separatedBy: keyword).count - 1
        }
        let rating = complexity > 20 ? "High" : (complexity > 10 ? "Medium" : "Low")
        return .structured(["score": .int(complexity), "rating": .string(rating)],
                           summary: "Complexity analysis for \(path): \(rating) (Cyclomatic approximation: \(complexity))")
    }

    func staticAnalysisFunctionSizeReport(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let threshold = max(5, call.int("threshold") ?? 60)
        let limit = max(1, min(300, call.int("limit") ?? 30))
        var rows: [(String, String, Int)] = []
        for url in Self.staticAnalysisSwiftFiles(under: root) {
            guard let lines = Self.staticAnalysisReadLines(url) else { continue }
            let rel = Self.staticAnalysisRelative(url, root: root)
            var i = 0
            while i < lines.count {
                guard let name = Self.staticAnalysisDeclaredFuncName(lines[i]) else { i += 1; continue }
                var depth = 0
                var started = false
                var j = i
                while j < lines.count {
                    let opens = lines[j].filter { $0 == "{" }.count
                    let closes = lines[j].filter { $0 == "}" }.count
                    if opens > 0 { started = true }
                    depth += opens - closes
                    if started && depth <= 0 { break }
                    j += 1
                }
                let length = j - i + 1
                if started && length >= threshold {
                    rows.append((name, "\(rel):\(i + 1)", length))
                }
                i = max(i + 1, j)
            }
        }
        rows.sort { $0.2 > $1.2 }
        if rows.isEmpty {
            return .structured(["count": .int(0)], summary: "No functions with \(threshold)+ lines found.")
        }
        var lines = ["Longest functions (≥\(threshold) lines, \(rows.count) total):"]
        lines += rows.prefix(limit).map { "- \($0.0) — \($0.1) (\($0.2) lines)" }
        return .structured(["count": .int(rows.count)], summary: lines.joined(separator: "\n"))
    }
}

extension YcodeMCPHost {
    // MARK: - Metrics, literals, deprecations, AST, concurrency, entry points

    func staticAnalysisCodeMetricsAnalyzer(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try fileReadingRequiredString(call, "path")
        let targetURL = try resolveFileReadingPath(path, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            throw MCPToolError("File or directory not found at: \(path)")
        }
        var filesToAnalyze: [URL] = []
        if isDir.boolValue {
            if let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" {
                        filesToAnalyze.append(fileURL)
                    }
                }
            }
        } else {
            if targetURL.pathExtension == "swift" {
                filesToAnalyze.append(targetURL)
            } else {
                throw MCPToolError("Target is not a Swift source file: \(path)")
            }
        }
        guard !filesToAnalyze.isEmpty else {
            throw MCPToolError("No Swift files found to analyze under: \(path)")
        }
        var totalLines = 0
        var totalBlank = 0
        var totalComments = 0
        var totalFunctions = 0
        var totalTypes = 0
        var totalBranches = 0
        for fileURL in filesToAnalyze {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            totalLines += lines.count
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    totalBlank += 1
                } else if trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                    totalComments += 1
                } else {
                    if trimmed.contains("func ") { totalFunctions += 1 }
                    if trimmed.contains("struct ") || trimmed.contains("class ") || trimmed.contains("enum ") || trimmed.contains("actor ") {
                        totalTypes += 1
                    }
                    if trimmed.contains("if ") || trimmed.contains("guard ") || trimmed.contains("for ") || trimmed.contains("while ") || trimmed.contains("case ") {
                        totalBranches += 1
                    }
                }
            }
        }
        let codeLines = totalLines - totalBlank - totalComments
        let commentRatio = codeLines > 0 ? Double(totalComments) / Double(codeLines) * 100.0 : 0.0
        let cyclomaticEst = totalFunctions > 0 ? (Double(totalBranches) / Double(totalFunctions)) + 1.0 : 1.0
        let output = """
        Code Metrics for '\(path)' (\(filesToAnalyze.count) Swift files):
        - Total Lines: \(totalLines)
        - Code Lines: \(codeLines)
        - Blank Lines: \(totalBlank)
        - Comment Lines: \(totalComments) (\(String(format: "%.1f", commentRatio))% comment ratio)
        - Declared Types (struct/class/enum/actor): \(totalTypes)
        - Functions: \(totalFunctions)
        - Decision Branches (if/guard/for/while/case): \(totalBranches)
        - Avg Cyclomatic Complexity per Function: ~\(String(format: "%.1f", cyclomaticEst))
        """
        return .text(output)
    }

    func staticAnalysisStringLiteralAudit(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let limit = max(1, min(1000, call.int("limit") ?? 100))
        let literalPattern = try? NSRegularExpression(pattern: #""([^"\\]|\\.){3,}""#)
        var findings: [String] = []
        for url in Self.staticAnalysisSwiftFiles(under: root) {
            guard let lines = Self.staticAnalysisReadLines(url) else { continue }
            let rel = Self.staticAnalysisRelative(url, root: root)
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                let lower = t.lowercased()
                if lower.contains("localizedstring") || lower.contains("string(localized") || lower.contains("localized:") { continue }
                if lower.contains("http") || lower.contains("bundle id") || lower.contains("identifier") { continue }
                guard let m = literalPattern?.matches(in: line, range: NSRange(line.startIndex..., in: line)), !m.isEmpty else { continue }
                let uiHints = ["text(", "title", "message", "placeholder", "label", "button(", "alert(", "navigationtitle"]
                if uiHints.contains(where: { lower.contains($0) }), let first = m.first, let r = Range(first.range, in: line) {
                    findings.append("\(rel):\(i + 1): \(String(line[r]).prefix(80))")
                    if findings.count >= limit { break }
                }
            }
            if findings.count >= limit { break }
        }
        if findings.isEmpty {
            return .structured(["count": .int(0)], summary: "No hardcoded user-facing string literals detected.")
        }
        var lines = ["Possibly unlocalized user-facing strings (\(findings.count)\(findings.count >= limit ? "+" : "")):"]
        lines += findings.map { "- \($0)" }
        return .structured(["count": .int(findings.count)], summary: lines.joined(separator: "\n"))
    }

    func staticAnalysisDeprecationUsageScan(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let limit = max(1, min(500, call.int("limit") ?? 100))
        var deprecatedNames = Set<String>()
        var declarations: [String] = []
        let declPattern = try? NSRegularExpression(pattern: #"@available\([^)]*deprecated[^)]*\)"#)
        let namePattern = try? NSRegularExpression(pattern: #"(?:func|class|struct|enum|var|let|typealias)\s+([A-Za-z_][\w]*)"#)
        var files: [(URL, [String])] = []
        for url in Self.staticAnalysisSwiftFiles(under: root) {
            guard let lines = Self.staticAnalysisReadLines(url) else { continue }
            files.append((url, lines))
            for (i, line) in lines.enumerated() {
                guard let dp = declPattern, dp.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                let next = lines.dropFirst(i + 1).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                if let m = namePattern?.firstMatch(in: next, range: NSRange(next.startIndex..., in: next)),
                   let r = Range(m.range(at: 1), in: next) {
                    let name = String(next[r])
                    deprecatedNames.insert(name)
                    declarations.append("\(name) — \(Self.staticAnalysisRelative(url, root: root)):\(i + 1)")
                }
            }
        }
        if declarations.isEmpty {
            return .structured(["declarationCount": .int(0), "usageCount": .int(0)],
                               summary: "No @available(*, deprecated) declarations found in workspace Swift sources.")
        }
        var usages: [String] = []
        // Legacy iterates an NSMutableSet (unordered); the port checks
        // names in sorted order so the listing is deterministic. The
        // set of findings is the same.
        for (url, lines) in files {
            let rel = Self.staticAnalysisRelative(url, root: root)
            for (i, line) in lines.enumerated() {
                for n in deprecatedNames.sorted() {
                    let pattern = try? NSRegularExpression(pattern: #"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: n) + #"\b"#)
                    if pattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil,
                       !(declPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil) {
                        usages.append("\(rel):\(i + 1): uses deprecated '\(n)'")
                        if usages.count >= limit { break }
                    }
                }
                if usages.count >= limit { break }
            }
            if usages.count >= limit { break }
        }
        var lines = ["Deprecated declarations (\(declarations.count)):"]
        lines += declarations.sorted().map { "- \($0)" }
        lines.append("Usage sites (\(usages.count)\(usages.count >= limit ? "+" : "")):")
        lines += usages.map { "- \($0)" }
        return .structured(["declarationCount": .int(declarations.count), "usageCount": .int(usages.count)],
                           summary: lines.joined(separator: "\n"))
    }

    /// Legacy's regex structural fallback, as the whole implementation:
    /// Legacy's primary path runs `xcrun swiftc -dump-ast`, which
    /// Ycode's MCP host does not do (no Swift toolchain here, and it
    /// does not shell out to Apple's toolchain). The fallback is
    /// Legacy's own behaviour when `swiftc` is unavailable, so the
    /// tool still returns real structural results.
    func staticAnalysisSwiftASTInspector(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let path = try fileReadingRequiredString(call, "path")
        let symbolFilter = call.arguments["symbol"]?.string
        guard let resolvedURL = resolveFileWritingPath(path, in: s) else {
            throw MCPToolError("File not found at path: \(path)")
        }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw MCPToolError("File not found at path: \(path)")
        }
        guard let content = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
            throw MCPToolError("Unable to read source file at \(path)")
        }
        var declarations: [String] = []
        let pattern = #"(class|struct|enum|protocol|extension|actor)\s+([A-Za-z0-9_]+)(\s*:\s*([^{]+))?"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = content as NSString
            let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let kind = nsString.substring(with: match.range(at: 1))
                let name = nsString.substring(with: match.range(at: 2))
                var inheritance = ""
                if match.numberOfRanges > 4 && match.range(at: 4).location != NSNotFound {
                    inheritance = " : " + nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                }
                if let sym = symbolFilter, !sym.isEmpty {
                    if name.localizedCaseInsensitiveContains(sym) {
                        declarations.append("- [\(kind)] \(name)\(inheritance)")
                    }
                } else {
                    declarations.append("- [\(kind)] \(name)\(inheritance)")
                }
            }
        }
        if declarations.isEmpty {
            return .text("No major type declarations found in \(path).")
        }
        return .text("Swift Structural AST Declarations in \(path):\n\n" + declarations.joined(separator: "\n"))
    }

    func staticAnalysisSwiftConcurrencyAnalyzer(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let path = try fileReadingRequiredString(call, "path")
        let targetURL = try resolveFileReadingPath(path, in: s)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw MCPToolError("Path not found: \(path)")
        }
        var filesToScan: [URL] = []
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir), isDir.boolValue {
            let enumerator = FileManager.default.enumerator(at: targetURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let u = enumerator?.nextObject() as? URL {
                if u.pathExtension == "swift" { filesToScan.append(u) }
            }
        } else {
            filesToScan.append(targetURL)
        }
        var findings: [String] = []
        for file in filesToScan {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Mutable global or static var outside an actor or
                // @MainActor. The @MainActor / actor check is file-wide,
                // as in Legacy.
                if (trimmed.hasPrefix("public static var ") || trimmed.hasPrefix("static var ") || trimmed.hasPrefix("var ")) &&
                   !trimmed.contains("let ") && !content.contains("@MainActor") && !content.contains("actor ") {
                    if !trimmed.contains("{") { // exclude computed properties
                        findings.append("`\(rel):\(idx + 1)`: Mutable shared state `\(trimmed)` without `@MainActor` or `actor` isolation.")
                    }
                }
                if trimmed.contains("DispatchQueue.main.sync") {
                    findings.append("`\(rel):\(idx + 1)`: `DispatchQueue.main.sync` call detected; high deadlock hazard on main actor.")
                }
                if trimmed.contains("@unchecked Sendable") {
                    findings.append("`\(rel):\(idx + 1)`: `@unchecked Sendable` used; verify manual synchronization mechanisms.")
                }
            }
        }
        var report = "### Swift 6 Strict Concurrency Analysis (\(filesToScan.count) files scanned):\n\n"
        if findings.isEmpty {
            report += "✅ Clean concurrency scan! No mutable globals, DispatchQueue.main.sync deadlocks, or unchecked Sendables detected."
        } else {
            report += "#### ⚠️ Concurrency Diagnostics (\(findings.count)):\n"
            for f in findings.prefix(25) {
                report += "- \(f)\n"
            }
        }
        return .text(report)
    }

    func staticAnalysisConcurrencyAudit(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let scanRoot = Self.staticAnalysisResolveScanPath(call.arguments["path"]?.string, in: s) else {
            throw MCPToolError("Invalid path: path must stay inside the workspace and must not contain '..'.")
        }
        let files = Self.staticAnalysisEnumerateSwiftFiles(at: scanRoot)
        if files.isEmpty {
            return .structured(["scannedFiles": .int(0), "findingCount": .int(0), "findings": .string("")],
                               summary: "Concurrency Audit: no Swift files found.")
        }
        guard let staticVarRegex = try? NSRegularExpression(pattern: "\\bstatic\\s+var\\s+([A-Za-z_][A-Za-z0-9_]*)", options: []),
              let funcRegex = try? NSRegularExpression(pattern: "\\bfunc\\b", options: []) else {
            throw MCPToolError("Concurrency Audit: failed to build scan patterns.")
        }
        var findings: [(relative: String, line: Int, issue: String)] = []
        for url in files {
            guard let text = Self.staticAnalysisReadText(url) else { continue }
            let relative = Self.staticAnalysisRelative(url, root: root)
            let lines = text.components(separatedBy: "\n")
            // File-level: SwiftUI types without @MainActor anywhere in
            // the file.
            if text.contains("import SwiftUI") && !text.contains("@MainActor") {
                for (index, line) in lines.enumerated() where line.contains(": View") || line.contains(": ObservableObject") || line.contains(": App") {
                    findings.append((relative: relative, line: index + 1, issue: "SwiftUI type without @MainActor in file (heuristic — verify whether main-actor isolation is needed)"))
                    break
                }
            }
            var braceDepth = 0
            var inAsyncFunction = false
            var asyncDepth = 0
            var index = 0
            while index < lines.count {
                let line = lines[index]
                let lineNumber = index + 1
                let range = NSRange(line.startIndex..., in: line)
                if line.contains("DispatchQueue.main.sync") {
                    findings.append((relative: relative, line: lineNumber, issue: "DispatchQueue.main.sync can deadlock when called from the main thread (heuristic)"))
                }
                if line.contains("nonisolated(unsafe)") {
                    findings.append((relative: relative, line: lineNumber, issue: "nonisolated(unsafe) bypasses Swift concurrency safety (heuristic — verify the access is actually safe)"))
                }
                if let match = staticVarRegex.firstMatch(in: line, options: [], range: range),
                   match.numberOfRanges >= 2, let nameRange = Range(match.range(at: 1), in: line) {
                    findings.append((relative: relative, line: lineNumber, issue: "Mutable static var '\(String(line[nameRange]))' shared across threads (heuristic — verify synchronization)"))
                }
                // Track async function bodies by brace depth.
                if funcRegex.firstMatch(in: line, options: [], range: range) != nil && line.contains("async") && !inAsyncFunction {
                    inAsyncFunction = true
                    asyncDepth = braceDepth
                }
                // Task block without await: scan ahead up to 40 lines.
                if line.contains("Task") && line.contains("{") {
                    var innerDepth = 0
                    var sawBrace = false
                    var hasAwait = false
                    var cursor = index
                    while cursor < lines.count && cursor < index + 41 {
                        let inner = lines[cursor]
                        if inner.contains("await") { hasAwait = true }
                        innerDepth += inner.filter { $0 == "{" }.count - inner.filter { $0 == "}" }.count
                        if innerDepth > 0 { sawBrace = true }
                        if sawBrace && innerDepth <= 0 { break }
                        cursor += 1
                    }
                    if sawBrace && !hasAwait {
                        findings.append((relative: relative, line: lineNumber, issue: "Task block without await (heuristic — verify the block does not need to suspend)"))
                    }
                }
                if inAsyncFunction, Self.staticAnalysisHasForceUnwrap(line) {
                    findings.append((relative: relative, line: lineNumber, issue: "Force unwrap inside an async function (heuristic — a nil crash here aborts the task)"))
                }
                braceDepth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                if inAsyncFunction && braceDepth <= asyncDepth {
                    inAsyncFunction = false
                }
                index += 1
                if findings.count >= 500 { break }
            }
            if findings.count >= 500 { break }
        }
        let capped = Array(findings.prefix(500))
        var output = "Concurrency Audit (heuristic): scanned \(files.count) Swift file(s), found \(findings.count) finding(s).\n"
        if capped.isEmpty {
            output += "No concurrency hazards found."
        } else {
            output += capped.map { "\($0.relative):\($0.line): \($0.issue)" }.joined(separator: "\n")
            if findings.count > capped.count {
                output += "\n… and \(findings.count - capped.count) more finding(s) omitted (listing capped at 500)."
            }
        }
        return .structured(["scannedFiles": .int(files.count), "findingCount": .int(findings.count),
                            "findings": .string(capped.map { "\($0.relative):\($0.line): \($0.issue)" }.joined(separator: "\n"))],
                           summary: output)
    }

    /// A force unwrap is "!" preceded by a value character (letter,
    /// digit, "_", ")", or "]") and not followed by "=" (which is
    /// "!="). Legacy's `hasForceUnwrap`, verbatim.
    nonisolated static func staticAnalysisHasForceUnwrap(_ line: String) -> Bool {
        let chars = Array(line)
        guard chars.count >= 2 else { return false }
        for index in 1..<chars.count {
            if chars[index] == "!" {
                let previous = chars[index - 1]
                let precededByValue = previous.isLetter || previous.isNumber || previous == "_" || previous == ")" || previous == "]"
                if precededByValue {
                    let next = index + 1 < chars.count ? chars[index + 1] : nil
                    if next != "=" {
                        return true
                    }
                }
            }
        }
        return false
    }

    func staticAnalysisEntryPointsDiscover(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var hits: [String] = []
        for url in Self.staticAnalysisSwiftFiles(under: root) {
            let rel = Self.staticAnalysisRelative(url, root: root)
            if url.lastPathComponent == "main.swift" {
                hits.append("\(rel): main.swift")
                continue
            }
            guard let lines = Self.staticAnalysisReadLines(url) else { continue }
            for (i, line) in lines.enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("@main") {
                    let next = lines.dropFirst(i + 1).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
                    hits.append("\(rel):\(i + 1): @main \(next.trimmingCharacters(in: .whitespaces).prefix(80))")
                } else if t.contains("class AppDelegate") || t.contains("class SceneDelegate") {
                    hits.append("\(rel):\(i + 1): \(t.prefix(100))")
                }
            }
            if hits.count > 200 { break }
        }
        if hits.isEmpty {
            return .structured(["count": .int(0)], summary: "No application entry points discovered (@main, main.swift, AppDelegate).")
        }
        return .structured(["count": .int(hits.count)], summary: "Entry points:\n" + hits.sorted().joined(separator: "\n"))
    }

    func staticAnalysisSwiftMigrationAdvisor(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let path = try fileReadingRequiredString(call, "path")
        let targetURL = try resolveFileReadingPath(path, in: s)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            throw MCPToolError("Path does not exist: \(path)")
        }
        let files = Self.staticAnalysisFilesForAnalysis(at: targetURL)
        var warnings: [String] = []
        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("//") { continue }
                if (trimmed.hasPrefix("public static var ") || trimmed.hasPrefix("static var ")) && !trimmed.contains("{") {
                    warnings.append("\(relPath):\(idx + 1) [Swift 6] Mutable static variable 'static var' without actor isolation violates strict concurrency. Protect with actor or mark 'nonisolated(unsafe)'.")
                }
                if trimmed.contains(": ObservableObject") {
                    warnings.append("\(relPath):\(idx + 1) [Swift 6 / Observation] Uses legacy 'ObservableObject'. Recommend migrating to Swift modern '@Observable'.")
                }
                if trimmed.contains("@Published ") {
                    warnings.append("\(relPath):\(idx + 1) [Swift 6 / Observation] Legacy '@Published' property wrapper. In Swift Observation framework, properties are observable by default.")
                }
            }
        }
        if warnings.isEmpty {
            return .text("Swift 6 Migration Audit passed: All analyzed code in '\(path)' conforms to Swift 6 strict concurrency patterns.")
        }
        return .text("Swift 6 Migration Advisor found \(warnings.count) migration opportunities across \(files.count) files in '\(path)':\n\n" + warnings.prefix(25).joined(separator: "\n") + (warnings.count > 25 ? "\n...and \(warnings.count - 25) more." : ""))
    }
}
