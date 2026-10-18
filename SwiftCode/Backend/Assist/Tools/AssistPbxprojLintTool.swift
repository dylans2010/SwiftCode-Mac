import Foundation

public struct AssistPbxprojLintTool: AssistTool {
    public let id = "pbxproj_lint"
    public let name = "pbxproj Lint"
    public let description = "Lints the .pbxproj: file references pointing at missing files, duplicate paths, and build files with dangling file references."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Lints the pbxproj.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        guard let pbxproj = AssistWorkspaceScan.findPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            return .failure("No .pbxproj found in the workspace.")
        }
        let projectDir = pbxproj.deletingLastPathComponent().deletingLastPathComponent()
        // File refs: id -> path (only entries with an explicit path).
        var fileRefPaths: [String: String] = [:]
        let refPattern = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* (.+?) \*/ = \{isa = PBXFileReference;[^}]*?path = ([^;]+);"#, options: [.dotMatchesLineSeparators])
        if let p = refPattern {
            for m in p.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r1 = Range(m.range(at: 1), in: text), let r3 = Range(m.range(at: 3), in: text) else { continue }
                fileRefPaths[String(text[r1])] = String(text[r3]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        var missing: [String] = []
        var seenPaths: Set<String> = []
        var duplicates: [String] = []
        for (id, path) in fileRefPaths {
            if seenPaths.contains(path) { duplicates.append("\(path) (ref \(id))") }
            seenPaths.insert(path)
            // Only check plain relative paths (skip absolute SDK paths).
            if !path.hasPrefix("/") {
                let candidate = projectDir.appendingPathComponent(path).standardized
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    missing.append("\(path) (ref \(id))")
                }
            }
            if missing.count > 200 { break }
        }
        // Build files referencing unknown fileRefs.
        let bfPattern = try? NSRegularExpression(pattern: #"fileRef = ([0-9A-F]{24}) /\* (.+?) \*/;"#)
        var dangling: [String] = []
        if let p = bfPattern {
            for m in p.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { continue }
                if fileRefPaths[String(text[r1])] == nil {
                    dangling.append("\(String(text[r2])) (fileRef \(String(text[r1])))")
                    if dangling.count > 100 { break }
                }
            }
        }
        var lines = ["pbxproj lint for \(pbxproj.lastPathComponent):"]
        lines.append("- File references: \(fileRefPaths.count)")
        lines.append("- Missing files on disk: \(missing.count)")
        lines += missing.sorted().prefix(30).map { "  MISSING: \($0)" }
        lines.append("- Duplicate paths: \(duplicates.count)")
        lines += duplicates.sorted().prefix(20).map { "  DUPLICATE: \($0)" }
        lines.append("- Dangling build-file refs: \(dangling.count)")
        lines += dangling.sorted().prefix(20).map { "  DANGLING: \($0)" }
        let clean = missing.isEmpty && duplicates.isEmpty && dangling.isEmpty
        return .success(lines.joined(separator: "\n"), data: [
            "fileRefCount": "\(fileRefPaths.count)",
            "missingCount": "\(missing.count)",
            "duplicateCount": "\(duplicates.count)",
            "danglingCount": "\(dangling.count)",
            "clean": clean ? "true" : "false"
        ])
    }
}
