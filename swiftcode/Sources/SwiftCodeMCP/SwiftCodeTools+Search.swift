import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The ported Legacy search / code-navigation tools (Wave 3).
///
/// Behaviour source: Legacy's `AssistSearchTool`,
/// `AssistRegexSearchTool`, `AssistSymbolSearchTool`,
/// `AssistCallHierarchyTool`, `AssistCodeSummaryTool`,
/// `AssistDependencyGraphTool`, `AssistImportGraphTool`,
/// `AssistProtocolConformanceListTool`, `SearchSkillsTool`,
/// `AssistSemanticQueryEngine`, `AssistSourceGraphBuilder`,
/// `AssistSymbolMoveFileTool`, `AssistSymbolReferenceGraphTool`,
/// `AssistSymbolRenameProjectTool`, `AssistTypeHierarchyTool` and
/// `AssistDataInspectionTools` (`extract_code_symbols`) (Dylan's own
/// code, ported under MIT), as specified in
/// `specs/ide/assist-search-git-tools.md` and the catalogue
/// (§§54–69). The workspace scan itself lives in
/// `SwiftCodeTools+SearchSupport.swift` (`SearchWorkspace`,
/// `SearchSkillIndex`).
///
/// Conventions, following Wave 1 (`SwiftCodeTools+FileReading.swift`) and
/// Wave 2 (`SwiftCodeTools+FileWriting.swift`):
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter Wave 1 adds to every tool. Legacy's
///   parameter-name aliases (`filePath`, `old_name`, `symbolName`, …)
///   are NOT supported: SwiftCode's argument validation rejects unknown
///   arguments before the handler runs (same as Wave 1).
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers and booleans) the way SwiftCode's other tools do — Legacy's
///   string-only map is not reproduced. Tools whose Legacy result
///   carries no data (`symbol_reference_graph`, `search_skills`)
///   return a plain text result instead.
/// * Path resolution is split the way Legacy splits it. Tools whose
///   Legacy implementation routes through the clamping
///   `AssistToolingSupport.resolvePath` (`code_summary`,
///   `dependency_graph`, `semantic_query_engine`,
///   `source_graph_builder`) use `resolveFileWritingClampedPath` (an
///   escaping path silently becomes the workspace root, never an
///   error). Tools with Legacy's strict per-tool resolvers
///   (`extract_code_symbols`, `symbol_move_file`,
///   `symbol_rename_project`) use `resolveFileWritingPath` (rejects
///   empty paths, NUL bytes, a leading `~` and any `..`). Tools with
///   no path parameter scan the workspace root.
/// * All 14 read-only tools are `readOnly: true, idempotent: true`,
///   `writes: false`. The two mutating tools (`symbol_move_file`,
///   `symbol_rename_project`) are `safeMutation` (`readOnly: false,
///   idempotent: true`, `writes: true`) and gate through `commit()`
///   — one approval per changed file, in order, stopping at the first
///   refusal (the Wave 2 multi-file shape). There is no Autopilot
///   bypass. `MCPServer.run` already refuses `writes: true` tools
///   when the server is read-only.
/// * Collisions with SwiftCode's existing tools: SwiftCode already has
///   `search` (workspace text search) and `symbol_search` (symbol
///   documentation). Legacy's `search_text` and `search_symbol` are
///   DIFFERENT tools with different IDs and schemas and are
///   registered as their own tools — nothing is merged or renamed.
///   Legacy's `search` alias for `search_text` is deliberately NOT
///   carried over (it would collide with SwiftCode's `search`); see the
///   catalogue §53.5.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `search_text` / `search_regex` results are sorted by path.
///   Legacy returns a dictionary (unordered); no caller could depend
///   on its order, so the port is deterministic instead.
/// * `semantic_query_engine` is a literal substring scan with three
///   keyword expansions (`view` / `model` / `service`), exactly as
///   Legacy implements it. Despite the name it performs no embedding
///   or LLM semantic search, and the port does not pretend otherwise.
/// * `symbol_rename_project` is a token-aware rename (gap
///   closure): identifier tokens from the swift-syntax parse, so
///   occurrences in comments, strings, and import paths are left
///   alone. It is still not a semantic rename: it has no Swift
///   symbol index, so shadowing is not resolved. The spec says so
///   plainly.
/// * `search_skills` searches the workspace's own skill files
///   (`SKILL.md` / `SKILLS.md` / `*.SKILL.md`, usually under
///   `.claude/skills/` or `.agents/skills/`). Legacy searched
///   `SkillIndex`, an Application Support library SwiftCode does not
///   have; the port searches the skill surface SwiftCode actually has,
///   with Legacy's metadata parsing and scoring. Its guidance lines
///   point at `file_read` (SwiftCode's canonical name) instead of
///   Legacy's `read_file` alias.
/// * `symbol_move_file`'s restore path is adapted to the gate: the
///   source file is committed first, then the destination. If the
///   destination commit fails, the source is restored to its
///   original content (a direct write that undoes an approved
///   change, net-zero) and the failure is reported. Verification
///   failure likewise restores both files. A destination approval
///   refusal therefore still leaves the workspace unchanged, as in
///   Legacy — only the mechanism differs.
/// * `resolveFileWritingPath` (strict) additionally rejects a
///   leading `~`; Legacy's private resolvers for `symbol_move_file`
///   / `symbol_rename_project` would have treated `~foo` as a
///   relative path under the root. A `~`-leading path fails either
///   way in practice, since no such file exists.
///
/// Wiring: the coordinator adds `searchTools` to `installTools()` in
/// `SwiftCodeTools.swift` (this file must not edit that file). The
/// registry aliases `search_dir` / `search_directory` / `find_file`
/// → `search_text` and `symbol_graph` → `symbol_reference_graph`
/// belong in `MCPServer.toolAliases` (also coordinator-owned); the
/// `search` → `search_text` alias is NOT carried over (see above).
extension SwiftCodeMCPHost {
    var searchTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("call_hierarchy", "Call Hierarchy",
                 "For a function name, finds its definition site, its callers across the workspace, and the functions it calls.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "function": Schema.string("Function name to analyze (without parameters).")],
                                      required: ["function"]),
                 output: ["type": "object",
                          "properties": .object(["function": Schema.str, "definitionCount": Schema.int, "callerCount": Schema.int,
                                                 "calleeCount": Schema.int]),
                          "required": .strings(["function", "definitionCount", "callerCount"])]) { h, call in
                try h.callHierarchy(call)
            },
            tool("code_summary", "Code Summary",
                 "Provides a high-level summary of a file or directory.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative file or directory path to summarize.")],
                                      required: ["path"]),
                 output: Schema.output(["summary": Schema.str])) { h, call in
                try h.codeSummary(call)
            },
            tool("dependency_graph", "Dependency Graph",
                 "Generates a graph of project dependencies.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory to scan. Defaults to the workspace root.")]),
                 output: Schema.output(["node_count": Schema.int, "edge_count": Schema.int, "nodes": Schema.str, "edges": Schema.str])) { h, call in
                try h.dependencyGraph(call)
            },
            tool("extract_code_symbols", "Extract Code Symbols",
                 "Extracts top-level declarations (class, struct, enum, protocol, actor, func, extension) and signatures from a source file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the Swift or source code file.")],
                                      required: ["path"]),
                 output: Schema.output(["path": Schema.str, "symbolCount": Schema.int])) { h, call in
                try h.extractCodeSymbols(call)
            },
            tool("import_graph", "Import Graph",
                 "Builds a file-level import graph: which modules each source file imports, and which files import a given module.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "module": Schema.string("Optional: only show files importing this module."),
                                       "limit": Schema.integer("Maximum files to report. Default 200.", minimum: 1)]),
                 output: ["type": "object",
                          "properties": .object(["module": Schema.str, "fileCount": Schema.int, "edgeCount": Schema.int,
                                                 "moduleCount": Schema.int]),
                          "required": .strings([])]) { h, call in
                try h.importGraph(call)
            },
            tool("protocol_conformance_list", "Protocol Conformance List",
                 "Lists every type that declares conformance to a given protocol, with declaration locations.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "protocol": Schema.string("Protocol name to search conformances for.")],
                                      required: ["protocol"]),
                 output: Schema.output(["protocol": Schema.str, "count": Schema.int])) { h, call in
                try h.protocolConformanceList(call)
            },
            tool("search_regex", "Regex Search",
                 "Searches for a regular expression pattern within the project files.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pattern": Schema.string("Regular expression pattern to search for.")],
                                      required: ["pattern"]),
                 output: Schema.output(["results": Schema.str])) { h, call in
                try h.searchRegex(call)
            },
            tool("search_skills", "Search Agent Skills",
                 "Search the workspace's local skills library (SKILL.md files under .claude/skills and .agents/skills) for specialized domain guides, architectures, workflows, and best practices. Call this tool when an objective involves a specific technology, framework, pattern, or task category.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Search keywords or task intent (e.g. 'SwiftUI architecture', 'TypeScript testing', 'Core Data', 'security audit')."),
                                       "limit": Schema.integer("Maximum number of matching skills to return (default: 8, max: 20).", minimum: 1)],
                                      required: ["query"])) { h, call in
                try h.searchSkills(call)
            },
            tool("search_symbol", "Symbol Search",
                 "Searches for symbols (classes, methods, variables) within the project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "symbol": Schema.string("Symbol name to search for.")],
                                      required: ["symbol"]),
                 output: Schema.output(["results": Schema.str])) { h, call in
                try h.searchSymbol(call)
            },
            tool("search_text", "Search Text",
                 "Searches for text across files in the project sandbox.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "pattern": Schema.string("Literal text pattern to find.")],
                                      required: ["pattern"]),
                 output: Schema.output(["results": Schema.str])) { h, call in
                try h.searchText(call)
            },
            tool("semantic_query_engine", "Semantic Source Query Engine",
                 "Performs semantic search for symbols, SwiftUI views, models, and services with usage context.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "query": Schema.string("Search query. Shortcuts: 'view', 'model', 'service' expand to common patterns."),
                                       "path": Schema.string("Workspace-relative directory to search. Defaults to the workspace root.")],
                                      required: ["query"]),
                 output: Schema.output(["matches": Schema.str])) { h, call in
                try h.semanticQuery(call)
            },
            tool("source_graph_builder", "Source Graph Builder",
                 "Parses Swift files and returns dependency and symbol relationship graph data.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative directory to scan. Defaults to the workspace root.")]),
                 output: Schema.output(["file_count": Schema.int, "node_count": Schema.int, "relationship_count": Schema.int,
                                        "imports": Schema.str, "relationships": Schema.str])) { h, call in
                try h.sourceGraph(call)
            },
            tool("symbol_move_file", "Move Symbol Across Files",
                 "Moves a top-level Swift declaration from a source file to a destination file by extracting its brace-balanced block, removing it from the source, and appending it to the destination. Verifies the symbol is present in the destination and its declaration is gone from the source, restoring both files on verification failure. Brace matching is heuristic and does not parse strings or comments.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "symbol": Schema.string("Name of the symbol to move."),
                                       "sourcePath": Schema.string("Workspace-relative path of the file containing the symbol."),
                                       "destinationPath": Schema.string("Workspace-relative path of the file receiving the symbol.")],
                                      required: ["symbol", "sourcePath", "destinationPath"]),
                 output: Schema.output(["symbol": Schema.str, "kind": Schema.str, "sourcePath": Schema.str,
                                        "destinationPath": Schema.str, "movedLines": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.moveSymbol(call)
            },
            tool("symbol_reference_graph", "Symbol Reference Graph",
                 "Traverses workspace files to identify declarations, references, and call sites for a given Swift symbol.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "symbol": Schema.string("Symbol name (e.g. MyViewModel, fetchUserData, UserRecord)."),
                                       "maxResults": Schema.integer("Maximum number of call sites to return (default: 50).")],
                                      required: ["symbol"])) { h, call in
                try h.symbolReferenceGraph(call)
            },
            tool("symbol_rename_project", "Rename Symbol Project-Wide",
                 "Renames a symbol across Swift files by renaming identifier tokens (swift-syntax parse): occurrences inside strings, comments, or import paths are left alone and reported as skipped. Only files that actually change are rewritten. Refuses when oldName equals newName or either name is not a valid Swift identifier. Syntactic, not semantic: shadowing is not resolved (no type checker or symbol index).",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "oldName": Schema.string("Existing symbol name to replace."),
                                       "newName": Schema.string("New symbol name. Letters, digits, and underscores only; must not start with a digit."),
                                       "path": Schema.string("Workspace-relative path of a file or directory to search. Defaults to the workspace root.")],
                                      required: ["oldName", "newName"]),
                 output: Schema.output(["filesChanged": Schema.str, "replacementCount": Schema.int, "changedFileCount": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.renameSymbolProject(call)
            },
            tool("type_hierarchy", "Type Hierarchy",
                 "Maps class/struct/enum/protocol declarations and their inheritance and conformance clauses across Swift sources.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "type": Schema.string("Optional: focus on one type name and show its ancestors/descendants.")]),
                 output: ["type": "object",
                          "properties": .object(["type": Schema.str, "childCount": Schema.int, "typeCount": Schema.int]),
                          "required": .strings([])]) { h, call in
                try h.typeHierarchy(call)
            },
        ]
    }

    // MARK: - Shared helpers for the search tools

    /// A required string argument; Legacy's missing-argument message.
    func searchRequiredString(_ call: MCPToolCall, _ key: String) throws -> String {
        guard let s = call.arguments[key]?.string else { throw MCPToolError("Missing required parameter: \(key)") }
        return s
    }

    /// A required string argument that must be non-blank after
    /// trimming; Legacy's missing-argument message.
    func searchRequiredTrimmedString(_ call: MCPToolCall, _ key: String) throws -> String {
        let raw = try searchRequiredString(call, key)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPToolError("Missing required parameter: \(key)") }
        return trimmed
    }

    /// The workspace root for a call.
    func searchRoot(_ call: MCPToolCall) throws -> URL {
        Self.folder(of: try session(for: call).model)
    }

    /// Legacy's identifier rule, shared by `symbol_move_file` and
    /// `symbol_rename_project`: letters, digits, and underscores only,
    /// and must not start with a digit.
    nonisolated static func isValidSearchIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "_"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard let first = value.unicodeScalars.first, !CharacterSet.decimalDigits.contains(first) else { return false }
        return true
    }

    // MARK: - Text search

    func searchText(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let pattern = try searchRequiredString(call, "pattern")
        let results: [(url: URL, matches: [String])]
        do {
            results = try SearchWorkspace.searchText(in: root, pattern: pattern, isRegex: false)
        } catch {
            throw MCPToolError("Search failed: \(error.localizedDescription)")
        }
        let formatted = results.map { (url, matches) in
            "\(SearchWorkspace.relative(url, root: root)):\n" + matches.joined(separator: "\n")
        }.joined(separator: "\n\n")
        return .structured(["results": .string(formatted)], summary: "Search results for '\(pattern)':")
    }

    func searchRegex(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let pattern = try searchRequiredString(call, "pattern")
        let results: [(url: URL, matches: [String])]
        do {
            results = try SearchWorkspace.searchText(in: root, pattern: pattern, isRegex: true)
        } catch {
            throw MCPToolError("Regex search failed: \(error.localizedDescription)")
        }
        let lines = results.flatMap { (url, matches) in
            let rel = SearchWorkspace.relative(url, root: root)
            return matches.map { "\(rel):\($0)" }
        }
        return .structured(["results": .string(lines.joined(separator: "\n"))],
                           summary: "Regex search completed for '\(pattern)'")
    }

    func searchSymbol(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let symbol = try searchRequiredString(call, "symbol")
        let escaped = NSRegularExpression.escapedPattern(for: symbol)
        let patterns = [
            "\\b(class|struct|enum|protocol|actor|typealias|extension)\\s+\(escaped)\\b",
            "\\bfunc\\s+\(escaped)\\s*[\\(<]",
            "\\b(var|let)\\s+\(escaped)\\s*[:=]",
            "\\bcase\\s+\(escaped)\\b",
        ]
        var allMatches: [String] = []
        for pattern in patterns {
            // A pattern that fails to compile is skipped and logged by
            // Legacy; the other patterns still run.
            guard let found = try? SearchWorkspace.searchText(in: root, pattern: pattern, isRegex: true) else { continue }
            for (url, matches) in found {
                let rel = SearchWorkspace.relative(url, root: root)
                allMatches.append(contentsOf: matches.map { "\(rel):\($0)" })
            }
        }
        let deduped = Array(Set(allMatches)).sorted()
        return .structured(["results": .string(deduped.joined(separator: "\n"))],
                           summary: "Symbol search completed for '\(symbol)'")
    }

    // MARK: - Symbol and declaration scans

    func extractCodeSymbols(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let pathRaw = try searchRequiredString(call, "path")
        // No separate empty check: Legacy's strict resolver rejects an
        // empty path with "Path is outside the workspace", not as a
        // missing argument.
        guard let fileURL = resolveFileWritingPath(pathRaw, in: s) else {
            throw MCPToolError("Path is outside the workspace: \(pathRaw)")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MCPToolError("File not found at: \(pathRaw)")
        }
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw MCPToolError("Failed to read and extract symbols from `\(pathRaw)`: \(error.localizedDescription)")
        }
        let lines = content.components(separatedBy: .newlines)
        let keywords = ["class ", "struct ", "enum ", "protocol ", "actor ", "func ", "extension ", "typealias "]
        var symbols: [(line: Int, kind: String, signature: String)] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("/*") && !trimmed.hasPrefix("*") else { continue }
            for kw in keywords where trimmed.contains(kw) {
                let signature = trimmed.components(separatedBy: "{").first?.trimmingCharacters(in: .whitespaces) ?? trimmed
                symbols.append((index + 1, kw.trimmingCharacters(in: .whitespaces), signature))
                break
            }
        }
        let symbolList = symbols.map { "  • L\($0.line): [\($0.kind)] \($0.signature)" }.joined(separator: "\n")
        let output = """
        Extracted \(symbols.count) declaration symbol(s) from `\(pathRaw)`:
        \(symbolList)
        """
        return .structured(["path": .string(pathRaw), "symbolCount": .int(symbols.count)], summary: output)
    }

    func callHierarchy(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let fn = try searchRequiredTrimmedString(call, "function")
        let files = SearchWorkspace.swiftFiles(under: root)
        var definitions: [String] = []
        var callers: [String] = []
        var callees: Set<String> = []
        let callPattern = try? NSRegularExpression(pattern: #"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: fn) + #"\s*\("#)
        let calleePattern = try? NSRegularExpression(pattern: #"(?<![\w.])([A-Za-z_][\w]*)\s*\("#)
        for url in files {
            guard let lines = SearchWorkspace.readLines(url) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            for (i, line) in lines.enumerated() {
                if let decl = SearchWorkspace.declaredFuncName(line), decl == fn {
                    definitions.append("\(rel):\(i + 1)")
                    var depth = line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                    var j = i + 1
                    while j < lines.count && j < i + 400 && depth > 0 {
                        depth += lines[j].filter { $0 == "{" }.count - lines[j].filter { $0 == "}" }.count
                        let matches = calleePattern?.matches(in: lines[j], range: NSRange(lines[j].startIndex..., in: lines[j]))
                            .compactMap { m -> String? in
                                guard let r = Range(m.range(at: 1), in: lines[j]) else { return nil }
                                return String(lines[j][r])
                            } ?? []
                        for m in matches where m != fn { callees.insert(m) }
                        j += 1
                    }
                } else if let p = callPattern,
                          p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil,
                          SearchWorkspace.declaredFuncName(line) == nil {
                    callers.append("\(rel):\(i + 1)")
                }
            }
        }
        if definitions.isEmpty && callers.isEmpty {
            // Legacy's not-found result carries no `calleeCount` key.
            return .structured(["function": .string(fn), "definitionCount": .int(0), "callerCount": .int(0)],
                               summary: "No definition or callers found for function '\(fn)'.")
        }
        var lines = ["Call hierarchy for '\(fn)':", "Definitions (\(definitions.count)):"]
        lines += definitions.prefix(20).map { "- \($0)" }
        lines.append("Callers (\(callers.count)):")
        lines += callers.prefix(50).map { "- \($0)" }
        if callers.count > 50 { lines.append("… [truncated: showing 50 of \(callers.count)]") }
        lines.append("Callees (\(callees.count) distinct):")
        lines += callees.sorted().prefix(50).map { "- \($0)" }
        return .structured(["function": .string(fn), "definitionCount": .int(definitions.count),
                            "callerCount": .int(callers.count), "calleeCount": .int(callees.count)],
                           summary: lines.joined(separator: "\n"))
    }

    func protocolConformanceList(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let proto = try searchRequiredTrimmedString(call, "protocol")
        let declPattern = try? NSRegularExpression(
            pattern: #"^\s*(?:\w+\s+)*(class|struct|enum|actor)\s+([A-Za-z_][\w]*)\s*:[^\{]*\b"# + NSRegularExpression.escapedPattern(for: proto) + #"\b"#)
        let extPattern = try? NSRegularExpression(
            pattern: #"^\s*extension\s+([A-Za-z_][\w]*)\s*:[^\{]*\b"# + NSRegularExpression.escapedPattern(for: proto) + #"\b"#)
        var conformers: [String] = []
        var extensions: [String] = []
        for url in SearchWorkspace.swiftFiles(under: root) {
            guard let lines = SearchWorkspace.readLines(url) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            for (i, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if let m = declPattern?.firstMatch(in: line, range: range),
                   let r = Range(m.range(at: 2), in: line) {
                    conformers.append("\(String(line[r])) — \(rel):\(i + 1)")
                } else if let m = extPattern?.firstMatch(in: line, range: range),
                          let r = Range(m.range(at: 1), in: line) {
                    extensions.append("extension \(String(line[r])) — \(rel):\(i + 1)")
                }
            }
        }
        let all = (conformers + extensions).sorted()
        if all.isEmpty {
            return .structured(["protocol": .string(proto), "count": .int(0)],
                               summary: "No conformances to protocol '\(proto)' found.")
        }
        return .structured(["protocol": .string(proto), "count": .int(all.count)],
                           summary: "Conformances to '\(proto)' (\(all.count)):\n" + all.map { "- \($0)" }.joined(separator: "\n"))
    }

    func typeHierarchy(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let focus = call.arguments["type"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        var decls: [String: (kind: String, parents: [String], loc: String)] = [:]
        let pattern = try? NSRegularExpression(
            pattern: #"^\s*(?:public|private|internal|fileprivate|open)?\s*(?:final\s+)?(class|struct|enum|protocol|actor)\s+([A-Za-z_][\w]*)\s*(?::\s*([^\{]+))?"#)
        for url in SearchWorkspace.swiftFiles(under: root) {
            guard let lines = SearchWorkspace.readLines(url) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            for (i, line) in lines.enumerated() {
                guard let p = pattern,
                      let m = p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      m.numberOfRanges >= 3,
                      let kr = Range(m.range(at: 1), in: line),
                      let nr = Range(m.range(at: 2), in: line) else { continue }
                let kind = String(line[kr])
                let name = String(line[nr])
                var parents: [String] = []
                if m.numberOfRanges >= 4, let pr = Range(m.range(at: 3), in: line) {
                    parents = String(line[pr]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                decls[name] = (kind, parents, "\(rel):\(i + 1)")
            }
        }
        if let focus, !focus.isEmpty {
            guard let d = decls[focus] else {
                throw MCPToolError("Type '\(focus)' not found in workspace Swift sources.")
            }
            var lines = ["Type hierarchy for '\(focus)' (\(d.kind)) at \(d.loc):", "Inherits/conforms to:"]
            lines += d.parents.isEmpty ? ["- (none)"] : d.parents.map { "- \($0)" }
            let children = decls.filter { $0.value.parents.contains(focus) }.map { "\($0.key) (\($0.value.kind))" }.sorted()
            lines.append("Subtypes (\(children.count)):")
            lines += children.isEmpty ? ["- (none)"] : children.map { "- \($0)" }
            return .structured(["type": .string(focus), "childCount": .int(children.count)],
                               summary: lines.joined(separator: "\n"))
        }
        var lines = ["Type declarations (\(decls.count) total):"]
        for name in decls.keys.sorted().prefix(200) {
            let d = decls[name]!
            let parents = d.parents.isEmpty ? "" : ": " + d.parents.joined(separator: ", ")
            lines.append("- \(d.kind) \(name)\(parents) — \(d.loc)")
        }
        if decls.count > 200 { lines.append("… [truncated: showing 200 of \(decls.count)]") }
        return .structured(["typeCount": .int(decls.count)], summary: lines.joined(separator: "\n"))
    }

    func symbolReferenceGraph(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let symbol = try searchRequiredTrimmedString(call, "symbol")
        let maxResults = call.int("maxResults") ?? 50
        var matches: [(file: String, line: Int, content: String, isDeclaration: Bool)] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            guard text.contains(symbol) else { continue }
            let relPath = SearchWorkspace.relative(fileURL, root: root)
            let lines = text.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                if line.contains(symbol) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let isDecl = trimmed.hasPrefix("func \(symbol)") ||
                        trimmed.hasPrefix("class \(symbol)") ||
                        trimmed.hasPrefix("struct \(symbol)") ||
                        trimmed.hasPrefix("enum \(symbol)") ||
                        trimmed.hasPrefix("protocol \(symbol)") ||
                        trimmed.hasPrefix("actor \(symbol)") ||
                        trimmed.hasPrefix("var \(symbol)") ||
                        trimmed.hasPrefix("let \(symbol)")
                    matches.append((file: relPath, line: idx + 1, content: trimmed, isDeclaration: isDecl))
                    if matches.count >= maxResults { break }
                }
            }
            if matches.count >= maxResults { break }
        }
        if matches.isEmpty {
            return .text("No references found for symbol '\(symbol)' in workspace.")
        }
        var report = "### Symbol Reference Graph for `\(symbol)` (\(matches.count) sites found):\n\n"
        let declarations = matches.filter { $0.isDeclaration }
        let usages = matches.filter { !$0.isDeclaration }
        if !declarations.isEmpty {
            report += "#### Declarations:\n"
            for d in declarations {
                report += "- `\(d.file):\(d.line)` → `\(d.content)`\n"
            }
            report += "\n"
        }
        report += "#### Usages & Call Sites:\n"
        for u in usages.prefix(40) {
            report += "- `\(u.file):\(u.line)` → `\(u.content)`\n"
        }
        return .text(report)
    }

    // MARK: - Summaries and graphs

    func codeSummary(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let pathRaw = try searchRequiredString(call, "path")
        let targetURL = resolveFileWritingClampedPath(pathRaw, in: s)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            throw MCPToolError("Path does not exist: \(pathRaw)")
        }
        if isDirectory.boolValue {
            let files = SearchWorkspace.enumeratedFiles(at: targetURL)
            let codeFiles = files.filter(SearchWorkspace.isCodeFile)
            let summary = "Directory \(pathRaw): \(files.count) files, \(codeFiles.count) code files"
            return .structured(["summary": .string(summary)], summary: "Summary for \(pathRaw)")
        }
        guard let content = try? String(contentsOf: targetURL, encoding: .utf8) else {
            throw MCPToolError("File at \(pathRaw) is not readable as UTF-8 text")
        }
        let lines = content.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let commentLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.count
        let summary = "File \(pathRaw): \(lines.count) lines (\(nonEmpty) non-empty), \(commentLines) comment lines"
        return .structured(["summary": .string(summary)], summary: "Summary for \(pathRaw)")
    }

    func dependencyGraph(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let scope = resolveFileWritingClampedPath(call.arguments["path"]?.string ?? ".", in: s)
        let files = SearchWorkspace.enumeratedFiles(at: scope, allowedExtensions: ["swift"], maxFileSize: 300_000)
        var nodes = Set<String>()
        var edges: [String] = []
        let importRegex = try? NSRegularExpression(pattern: "^\\s*import\\s+([A-Za-z0-9_\\.]+)", options: [.anchorsMatchLines])
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8), let importRegex else { continue }
            let source = SearchWorkspace.relative(file, root: root)
            nodes.insert(source)
            let nsRange = NSRange(location: 0, length: content.utf16.count)
            for match in importRegex.matches(in: content, options: [], range: nsRange) {
                guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: content) else { continue }
                let module = String(content[r])
                nodes.insert(module)
                edges.append("\(source) -> \(module)")
            }
        }
        return .structured(["node_count": .int(nodes.count), "edge_count": .int(edges.count),
                            "nodes": .string(nodes.sorted().joined(separator: ", ")),
                            "edges": .string(edges.sorted().joined(separator: "\n"))],
                           summary: "Dependency graph generated for \(files.count) files.")
    }

    func importGraph(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        let module = call.arguments["module"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(2000, call.int("limit") ?? 200))
        let importPattern = try? NSRegularExpression(pattern: #"^\s*import\s+([A-Za-z_][\w.]*)"#)
        var edges: [(file: String, module: String)] = []
        var moduleCounts: [String: Int] = [:]
        for url in SearchWorkspace.files(under: root, extensions: SearchWorkspace.sourceExts) {
            guard let lines = SearchWorkspace.readLines(url) else { continue }
            let rel = SearchWorkspace.relative(url, root: root)
            for line in lines {
                guard let m = importPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let r = Range(m.range(at: 1), in: line) else { continue }
                let mod = String(line[r])
                if let module, mod != module { continue }
                edges.append((rel, mod))
                moduleCounts[mod, default: 0] += 1
            }
        }
        if let module {
            let files = Array(Set(edges.map { $0.file })).sorted()
            var lines = ["Files importing '\(module)' (\(files.count)):"]
            lines += files.prefix(limit).map { "- \($0)" }
            return .structured(["module": .string(module), "fileCount": .int(files.count)],
                               summary: lines.joined(separator: "\n"))
        }
        var lines = ["Most-imported modules:"]
        for (mod, count) in moduleCounts.sorted(by: { $0.value > $1.value }).prefix(30) {
            lines.append("- \(mod): \(count) files")
        }
        lines.append("Import edges (\(edges.count) total, showing \(min(limit, edges.count))):")
        lines += edges.prefix(limit).map { "- \($0.file) -> \($0.module)" }
        return .structured(["edgeCount": .int(edges.count), "moduleCount": .int(moduleCounts.count)],
                           summary: lines.joined(separator: "\n"))
    }

    func sourceGraph(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let scope = resolveFileWritingClampedPath(call.arguments["path"]?.string ?? ".", in: s)
        guard FileManager.default.fileExists(atPath: scope.path) else {
            throw MCPToolError("Path does not exist: \(scope.path)")
        }
        let files = SearchWorkspace.enumeratedFiles(at: scope, allowedExtensions: ["swift"], maxFileSize: 800_000)
        var nodes = Set<String>()
        var imports = Set<String>()
        var relationships: [String] = []
        let symbolRegex = try NSRegularExpression(pattern: "\\b(class|struct|enum|protocol|func)\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [])
        let typeUseRegex = try NSRegularExpression(pattern: "\\b([A-Z][A-Za-z0-9_]*)\\b", options: [])
        let importRegex = try NSRegularExpression(pattern: "^\\s*import\\s+([A-Za-z0-9_\\.]+)", options: [.anchorsMatchLines])
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let rel = SearchWorkspace.relative(file, root: root)
            nodes.insert(rel)
            let range = NSRange(location: 0, length: content.utf16.count)
            var fileSymbols: [String] = []
            for match in symbolRegex.matches(in: content, options: [], range: range) {
                guard let kindRange = Range(match.range(at: 1), in: content),
                      let nameRange = Range(match.range(at: 2), in: content) else { continue }
                let symbol = "\(content[kindRange]):\(content[nameRange])"
                nodes.insert(symbol)
                relationships.append("\(rel) -> \(symbol)")
                fileSymbols.append(String(content[nameRange]))
            }
            for match in importRegex.matches(in: content, options: [], range: range) {
                guard let importRange = Range(match.range(at: 1), in: content) else { continue }
                let module = String(content[importRange])
                imports.insert(module)
                nodes.insert("module:\(module)")
                relationships.append("\(rel) -> module:\(module)")
            }
            for match in typeUseRegex.matches(in: content, options: [], range: range) {
                guard let r = Range(match.range(at: 1), in: content) else { continue }
                let usedType = String(content[r])
                if fileSymbols.contains(usedType) { continue }
                relationships.append("\(rel) -> type:\(usedType)")
            }
        }
        return .structured(["file_count": .int(files.count), "node_count": .int(nodes.count),
                            "relationship_count": .int(relationships.count),
                            "imports": .string(imports.sorted().joined(separator: ",")),
                            "relationships": .string(relationships.prefix(2000).joined(separator: "\n"))],
                           summary: "Built source graph for \(files.count) Swift files.")
    }

    func semanticQuery(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let query = try searchRequiredTrimmedString(call, "query")
        let scope = resolveFileWritingClampedPath(call.arguments["path"]?.string ?? ".", in: s)
        let files = SearchWorkspace.enumeratedFiles(at: scope, allowedExtensions: ["swift"], maxFileSize: 800_000)
        var hits: [String] = []
        let q = query.lowercased()
        for file in files {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let lc = line.lowercased()
                let isSemanticClass = (q == "view" && line.contains(": View")) ||
                    (q == "model" && (line.contains("struct") || line.contains("class")) && (lc.contains("model") || lc.contains("viewmodel"))) ||
                    (q == "service" && lc.contains("service"))
                if lc.contains(q) || isSemanticClass {
                    let start = max(0, idx - 1)
                    let end = min(lines.count - 1, idx + 1)
                    let snippet = (start...end).map { "\($0 + 1): \(lines[$0])" }.joined(separator: " | ")
                    hits.append("\(SearchWorkspace.relative(file, root: root))::\(idx + 1)::\(snippet)")
                }
            }
        }
        return .structured(["matches": .string(hits.prefix(1500).joined(separator: "\n"))],
                           summary: "Semantic query returned \(hits.count) matches.")
    }

    // MARK: - Skills

    func searchSkills(_ call: MCPToolCall) throws -> MCPToolResult {
        let root = try searchRoot(call)
        guard let query = call.arguments["query"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            throw MCPToolError("Missing required parameter 'query'.")
        }
        let limit = min(20, max(1, call.int("limit") ?? 8))
        let matches = SearchSkillIndex.search(query: query, limit: limit, in: root)
        if matches.isEmpty {
            return .text("No skills found matching query '\(query)'. You can continue executing the task using standard engineering principles.")
        }
        var output = "### Discovered Skills Matching '\(query)' (\(matches.count) results):\n\n"
        for (idx, skill) in matches.enumerated() {
            output += "\(idx + 1). **\(skill.name)** (`\(skill.id)`)\n"
            output += "   - **Source**: \(skill.sourceKind) (\(skill.sourceDescription))\n"
            output += "   - **Location**: `\(skill.path)`\n"
            output += "   - **Description**: \(skill.description)\n"
            if !skill.tags.isEmpty {
                output += "   - **Tags**: \(skill.tags.joined(separator: ", "))\n"
            }
            if !skill.recommendedTools.isEmpty {
                output += "   - **Tools**: \(skill.recommendedTools.joined(separator: ", "))\n"
            }
            output += "   - *To follow this skill, inspect instructions using `file_read` on `\(skill.path)`.*\n\n"
        }
        output += "\n> **Guidance**: Inspect the most relevant skill above using `file_read` if detailed execution instructions or rules are needed."
        return .text(output)
    }

    // MARK: - Mutating tools (approval-gated)

    func moveSymbol(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        guard let symbol = call.arguments["symbol"]?.string, !symbol.isEmpty else {
            throw MCPToolError("Missing required parameter: symbol")
        }
        guard let sourceRaw = call.arguments["sourcePath"]?.string, !sourceRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: sourcePath")
        }
        guard let destinationRaw = call.arguments["destinationPath"]?.string, !destinationRaw.isEmpty else {
            throw MCPToolError("Missing required parameter: destinationPath")
        }
        guard Self.isValidSearchIdentifier(symbol) else {
            throw MCPToolError("Invalid symbol '\(symbol)': identifiers may contain only letters, digits, and underscores, and must not start with a digit.")
        }
        guard let sourceURL = resolveFileWritingPath(sourceRaw, in: s) else {
            throw MCPToolError("Invalid sourcePath: path must stay inside the workspace and must not contain '..'.")
        }
        guard let destinationURL = resolveFileWritingPath(destinationRaw, in: s) else {
            throw MCPToolError("Invalid destinationPath: path must stay inside the workspace and must not contain '..'.")
        }
        guard sourceURL.standardized != destinationURL.standardized else {
            throw MCPToolError("Refusing move: sourcePath and destinationPath must differ.")
        }
        guard let sourceContent = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw MCPToolError("Could not read source file at \(relative(sourceURL.path, in: s)).")
        }
        guard let destinationContent = try? String(contentsOf: destinationURL, encoding: .utf8) else {
            throw MCPToolError("Could not read destination file at \(relative(destinationURL.path, in: s)).")
        }
        let declPattern = "\\b(func|class|struct|enum|protocol|actor|var|let|typealias)\\s+" + NSRegularExpression.escapedPattern(for: symbol) + "\\b"
        guard let declRegex = try? NSRegularExpression(pattern: declPattern, options: []) else {
            throw MCPToolError("Move failed: could not build a declaration pattern for '\(symbol)'.")
        }
        let destinationRange = NSRange(destinationContent.startIndex..., in: destinationContent)
        if declRegex.firstMatch(in: destinationContent, options: [], range: destinationRange) != nil {
            throw MCPToolError("Refusing move: destination already declares '\(symbol)'.")
        }
        let sourceLines = sourceContent.components(separatedBy: "\n")
        var declarationLine: Int? = nil
        var declarationKind = ""
        for (index, line) in sourceLines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            if let match = declRegex.firstMatch(in: line, options: [], range: range),
               match.numberOfRanges >= 2, let kindRange = Range(match.range(at: 1), in: line) {
                declarationLine = index
                declarationKind = String(line[kindRange])
                break
            }
        }
        guard let startIndex = declarationLine else {
            throw MCPToolError("Symbol '\(symbol)' declaration not found in \(relative(sourceURL.path, in: s)).")
        }
        // Extract the brace-balanced block starting at the declaration
        // line (Legacy's heuristic: brace counting, no string/comment
        // parsing; 500-line cap; 20-line no-brace rule).
        var depth = 0
        var sawBrace = false
        var endIndex: Int? = nil
        let limit = min(sourceLines.count, startIndex + 501)
        for index in startIndex..<limit {
            let line = sourceLines[index]
            let opens = line.filter { $0 == "{" }.count
            let closes = line.filter { $0 == "}" }.count
            if opens > 0 { sawBrace = true }
            depth += opens - closes
            if sawBrace && depth <= 0 { endIndex = index; break }
            if !sawBrace && index - startIndex >= 20 { break }
        }
        if sawBrace {
            guard let end = endIndex else {
                throw MCPToolError("Move failed: declaration block for '\(symbol)' is unbalanced or exceeds 500 lines.")
            }
            endIndex = end
        } else if declarationKind == "var" || declarationKind == "let" || declarationKind == "typealias" {
            endIndex = startIndex
        } else {
            throw MCPToolError("Move failed: could not find the opening brace for '\(symbol)' (\(declarationKind)) within 20 lines of its declaration.")
        }
        guard let end = endIndex else {
            throw MCPToolError("Move failed: could not determine the declaration block for '\(symbol)'.")
        }
        let blockLines = Array(sourceLines[startIndex...end])
        var remainingLines = sourceLines
        remainingLines.removeSubrange(startIndex...end)
        let newSource = remainingLines.joined(separator: "\n")
        var newDestination = destinationContent
        if !newDestination.isEmpty && !newDestination.hasSuffix("\n") {
            newDestination += "\n"
        }
        newDestination += "\n" + blockLines.joined(separator: "\n") + "\n"

        let sourceRel = relative(sourceURL.path, in: s)
        let destinationRel = relative(destinationURL.path, in: s)
        // Gate: one commit() per file, source first, then destination
        // (the Wave 2 multi-file shape). If the destination commit
        // fails after the source commit, the source is restored to its
        // original content — Legacy's restore path, adapted to the
        // gate (a direct write undoing an approved change, net-zero).
        try await commit(MCPChange(tool: call.name, path: sourceURL.path, relativePath: sourceRel,
                                   original: sourceContent, proposed: newSource,
                                   summary: "Move \(symbol) out of \(sourceRel)"), call: call, session: s)
        do {
            try await commit(MCPChange(tool: call.name, path: destinationURL.path, relativePath: destinationRel,
                                       original: destinationContent, proposed: newDestination,
                                       summary: "Move \(symbol) into \(destinationRel)"), call: call, session: s)
        } catch {
            try? sourceContent.write(to: sourceURL, atomically: true, encoding: .utf8)
            s.noteFileEdited(sourceURL.path)
            delegate?.mcpHostDidWrite(sourceURL.path)
            throw error
        }
        // Verify: declaration present in destination, gone from source.
        let verifySource = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        let verifyDestination = (try? String(contentsOf: destinationURL, encoding: .utf8)) ?? ""
        let sourceRange = NSRange(verifySource.startIndex..., in: verifySource)
        let destRange = NSRange(verifyDestination.startIndex..., in: verifyDestination)
        let stillInSource = declRegex.firstMatch(in: verifySource, options: [], range: sourceRange) != nil
        let presentInDestination = declRegex.firstMatch(in: verifyDestination, options: [], range: destRange) != nil
        if stillInSource || !presentInDestination {
            try? sourceContent.write(to: sourceURL, atomically: true, encoding: .utf8)
            try? destinationContent.write(to: destinationURL, atomically: true, encoding: .utf8)
            s.noteFileEdited(sourceURL.path)
            s.noteFileEdited(destinationURL.path)
            delegate?.mcpHostDidWrite(sourceURL.path)
            delegate?.mcpHostDidWrite(destinationURL.path)
            throw MCPToolError("Move verification failed (still in source: \(stillInSource), in destination: \(presentInDestination)). Original contents were restored.")
        }
        return .structured(["symbol": .string(symbol), "kind": .string(declarationKind),
                            "sourcePath": .string(sourceRel), "destinationPath": .string(destinationRel),
                            "movedLines": .int(blockLines.count)],
                           summary: "Moved symbol '\(symbol)' (\(declarationKind), \(blockLines.count) line(s)) from \(sourceRel) to \(destinationRel).")
    }

    /// Gap closure: token-aware rename (`SymbolRenameEngine` —
    /// identifier tokens from the swift-syntax parse, never raw
    /// text). See `specs/ide/gap-closure-correctness.md` §6.
    func renameSymbolProject(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await correctnessRenameSymbolProject(call)
    }

    /// Legacy's `AssistSymbolRenameProjectTool.enumerateSwiftFiles`: a
    /// single `.swift` file (≤ 300 KB) on its own, else a recursive
    /// walk that skips `.git` / `DerivedData` / `.build` / `Pods` /
    /// `node_modules` directories, `.swift` files only, ≤ 300 KB, at
    /// most 5000 files, sorted by path. Hidden files are NOT skipped
    /// (the enumerator uses no skip options).
    nonisolated static func renameScopeFiles(at root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            if root.pathExtension.lowercased() == "swift", searchFileSize(root) <= 300_000 { return [root] }
            return []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                              options: []) else { return results }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if name == ".git" || name == "DerivedData" || name == ".build" || name == "Pods" || name == "node_modules" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() != "swift" { continue }
            if searchFileSize(url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    nonisolated static func searchFileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
}
