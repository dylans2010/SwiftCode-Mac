// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistSwiftASTInspectorTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/AssistSwiftASTInspectorTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Raw swiftc -dump-ast output (the type-checked AST dump, up to 250 lines, with symbol filtering)
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+StaticAnalysis.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

//
//  AssistSwiftASTInspectorTool.swift
//  SwiftCode
//

import Foundation
import SwiftCodeAssistant

public struct AssistSwiftASTInspectorTool: AssistTool {
    public let id = "swift_ast_inspector"
    public let name = "Swift AST Inspector"
    public let description = "Inspects the abstract syntax tree (AST) and type declaration hierarchy of a Swift source file."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Dumps and parses the Swift AST or structural declaration hierarchy of a workspace file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Relative path to the Swift file within the workspace."),
                "symbol": JSONSchema(type: "string", description: "Optional symbol name to filter AST declarations for.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        let symbolFilter = input["symbol"] as? String

        let resolvedURL: URL
        if path.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: path)
        } else {
            resolvedURL = context.workspaceRoot.appendingPathComponent(path)
        }

        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return .failure("File not found at path: \(path)")
        }

        // Run swiftc -dump-ast
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["swiftc", "-dump-ast", resolvedURL.path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let rawAST = String(decoding: data, as: UTF8.self)

            if !rawAST.isEmpty && !rawAST.contains("error:") {
                var lines = rawAST.components(separatedBy: .newlines)
                if let sym = symbolFilter, !sym.isEmpty {
                    lines = lines.filter { $0.localizedCaseInsensitiveContains(sym) }
                }
                let truncated = lines.prefix(250).joined(separator: "\n")
                return .success("AST for \(path) (\(lines.count) lines):\n\n\(truncated)")
            }
        } catch {
            // Fall through to regex-based structural AST fallback
        }

        // Structural parser fallback: extracts classes, structs, enums, protocols, funcs, extensions
        guard let content = try? String(contentsOf: resolvedURL, encoding: .utf8) else {
            return .failure("Unable to read source file at \(path)")
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
            return .success("No major type declarations found in \(path).")
        } else {
            return .success("Swift Structural AST Declarations in \(path):\n\n" + declarations.joined(separator: "\n"))
        }
    }
}
