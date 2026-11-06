import Foundation

public struct AssistTargetSourceListTool: AssistTool {
    public let id = "target_source_list"
    public let name = "Target Source List"
    public let description = "Lists the source files compiled into a given Xcode target (Compile Sources build phase), resolved from the .pbxproj."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists a target's compiled sources.",
            properties: [
                "target": JSONSchema(type: "string", description: "Target name. If omitted, lists sources for every target (truncated per target)."),
                "limit": JSONSchema(type: "integer", description: "Maximum files per target. Default 200.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let wanted = (input["target"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(2000, (input["limit"] as? Int) ?? 200))
        guard let pbxproj = AssistWorkspaceScan.findPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            return .failure("No .pbxproj found in the workspace.")
        }
        // File refs: id -> path.
        var fileRefPaths: [String: String] = [:]
        if let p = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* (.+?) \*/ = \{isa = PBXFileReference;[^}]*?path = ([^;]+);"#, options: [.dotMatchesLineSeparators]) {
            for m in p.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r1 = Range(m.range(at: 1), in: text), let r3 = Range(m.range(at: 3), in: text) {
                    fileRefPaths[String(text[r1])] = String(text[r3]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
        }
        // Sources phases: id -> target name (via the target block's buildPhases list is complex;
        // instead map phase id -> files, then attribute phases to targets by proximity scan).
        // Practical approach: for each PBXNativeTarget block, extract its Sources phase ids,
        // then resolve each phase's files.
        var targetSources: [(String, [String])] = []
        guard let targetBlockPattern = try? NSRegularExpression(
            pattern: #"([0-9A-F]{24}) /\* (.+?) \*/ = \{\s*isa = PBXNativeTarget;(.*?)buildPhases = \((.*?)\); "#,
            options: [.dotMatchesLineSeparators]
        ) else {
            return .failure("Internal regex error.")
        }
        let phaseIdPattern = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* Sources \*/"#)
        for tm in targetBlockPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let nr = Range(tm.range(at: 2), in: text), let br = Range(tm.range(at: 4), in: text) else { continue }
            let targetName = String(text[nr])
            if let wanted, !wanted.isEmpty, targetName != wanted { continue }
            let phasesBlock = String(text[br])
            let phaseIds = phaseIdPattern?.matches(in: phasesBlock, range: NSRange(phasesBlock.startIndex..., in: phasesBlock)).compactMap { pm -> String? in
                guard let r = Range(pm.range(at: 1), in: phasesBlock) else { return nil }
                return String(phasesBlock[r])
            } ?? []
            var sources: [String] = []
            for phaseId in phaseIds {
                // Find the PBXSourcesBuildPhase block and its fileRef ids.
                let phasePattern = try? NSRegularExpression(
                    pattern: phaseId + #" /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);"#,
                    options: [.dotMatchesLineSeparators]
                )
                guard let pp = phasePattern,
                      let pm = pp.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let fr = Range(pm.range(at: 1), in: text) else { continue }
                let filesBlock = String(text[fr])
                // Each build file: `<id> /* X in Sources */ = {isa = PBXBuildFile; fileRef = <refId> ...`
                if let bp = try? NSRegularExpression(pattern: #"fileRef = ([0-9A-F]{24})"#) {
                    for bm in bp.matches(in: filesBlock, range: NSRange(filesBlock.startIndex..., in: filesBlock)) {
                        if let r = Range(bm.range(at: 1), in: filesBlock),
                           let path = fileRefPaths[String(filesBlock[r])] {
                            sources.append(path)
                        }
                    }
                }
            }
            targetSources.append((targetName, sources.sorted()))
        }
        if targetSources.isEmpty {
            if let wanted, !wanted.isEmpty {
                return .failure("Target '\(wanted)' not found in the pbxproj.")
            }
            return .failure("No target source phases parsed from the pbxproj.")
        }
        var lines = ["Target sources:"]
        for (name, sources) in targetSources {
            lines.append("- \(name) (\(sources.count) files):")
            lines += sources.prefix(limit).map { "    \($0)" }
            if sources.count > limit { lines.append("    … [truncated: showing \(limit) of \(sources.count)]") }
        }
        return .success(lines.joined(separator: "\n"), data: [
            "targetCount": "\(targetSources.count)"
        ])
    }
}
