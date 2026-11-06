import Foundation

public struct AssistReadmeGenerateTool: AssistTool {
    public let id = "readme_generate"
    public let name = "README Generate"
    public let description = "Generates a README.md skeleton from real repository inspection: project name, build systems, targets, structure, and entry points."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generates a README skeleton.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative output path. Default: README.generated.md."),
                "overwrite": JSONSchema(type: "boolean", description: "Overwrite if the file exists. Default false.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let rawPath = ((input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "README.generated.md"
        let overwrite = (input["overwrite"] as? Bool) ?? false
        guard let url = AssistWorkspacePaths.resolve(rawPath, workspaceRoot: root) else {
            return .failure("Refusing to write outside the workspace: \(rawPath)")
        }
        if FileManager.default.fileExists(atPath: url.path) && !overwrite {
            return .failure("File already exists at \(rawPath). Pass overwrite: true to replace it.")
        }
        let projectName = root.lastPathComponent
        // Build systems.
        var systems: [String] = []
        let fm = FileManager.default
        if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { systems.append("SwiftPM") }
        if (try? fm.contentsOfDirectory(atPath: root.path))?.contains(where: { $0.hasSuffix(".xcworkspace") }) == true { systems.append("Xcode workspace") }
        else if (try? fm.contentsOfDirectory(atPath: root.path))?.contains(where: { $0.hasSuffix(".xcodeproj") }) == true { systems.append("Xcode project") }
        if fm.fileExists(atPath: root.appendingPathComponent("Podfile").path) { systems.append("CocoaPods") }
        // Targets from pbxproj.
        var targets: [String] = []
        if let pbxproj = AssistWorkspaceScan.findPbxproj(in: root),
           let text = try? String(contentsOf: pbxproj, encoding: .utf8),
           let pattern = try? NSRegularExpression(pattern: #"/\* (\w[\w ]*) \*/ = \{\s*isa = PBXNativeTarget;"#) {
            targets = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m -> String? in
                guard let r = Range(m.range(at: 1), in: text) else { return nil }
                return String(text[r])
            }.sorted()
        }
        let swiftCount = AssistWorkspaceScan.swiftFiles(under: root).count
        var md = "# \(projectName)\n\n"
        md += "Generated README skeleton — fill in the project description, screenshots, and usage details.\n\n"
        md += "## Overview\n\n- Workspace: `\(projectName)`\n- Swift source files: \(swiftCount)\n"
        if !systems.isEmpty { md += "- Build systems: \(systems.joined(separator: ", "))\n" }
        if !targets.isEmpty {
            md += "\n## Targets\n\n"
            for t in targets { md += "- \(t)\n" }
        }
        md += "\n## Building\n\n"
        if systems.contains("SwiftPM") { md += "```sh\nswift build\n```\n\n" }
        if systems.contains("Xcode workspace") || systems.contains("Xcode project") {
            md += "Open the workspace in Xcode and build with ⌘B, or:\n\n```sh\nxcodebuild -scheme <Scheme> -configuration Debug build\n```\n\n"
        }
        md += "## Project Structure\n\nSee the repository layout for module organization.\n\n"
        md += "## License\n\nAdd license information here.\n"
        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write README: \(error.localizedDescription)")
        }
        return .success("README skeleton written to \(rawPath).", data: ["path": rawPath], filesChanged: [rawPath])
    }
}
