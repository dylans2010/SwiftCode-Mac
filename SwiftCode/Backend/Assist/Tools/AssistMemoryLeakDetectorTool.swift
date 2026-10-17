import Foundation

public struct AssistMemoryLeakDetectorTool: AssistTool {
    public let id = "memory_leak_detector"
    public let name = "Memory Leak Detector"
    public let description = "Scans Swift source code for retain cycles, strong self capture in escaping closures, and unowned reference risks."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scan Swift files for retain cycle patterns and memory leak hazards.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to a Swift file or directory.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }

        let targetURL = context.workspaceRoot.appendingPathComponent(path)
        let fileManager = FileManager.default

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDir) else {
            return .failure("Path not found: \(path)")
        }

        var files: [URL] = []
        if isDir.boolValue {
            if let enumerator = fileManager.enumerator(at: targetURL, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" {
                        files.append(fileURL)
                    }
                }
            }
        } else if targetURL.pathExtension == "swift" {
            files.append(targetURL)
        }

        var findings: [String] = []

        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = fileURL.path.replacingOccurrences(of: context.workspaceRoot.path + "/", with: "")
            let lines = content.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("//") { continue }

                // 1. Strong self capture in escaping closure
                if (trimmed.contains(".sink") || trimmed.contains("Task {") || trimmed.contains("DispatchQueue.")) && trimmed.contains("self.") && !trimmed.contains("[weak self]") && !trimmed.contains("[unowned self]") {
                    findings.append("\(relPath):\(idx + 1) Potential retain cycle: escaping closure captures strong 'self'. Consider adding '[weak self]'.")
                }

                // 2. Unowned self hazard in async / network call
                if trimmed.contains("[unowned self]") && (trimmed.contains("async") || trimmed.contains("await") || trimmed.contains("URLSession")) {
                    findings.append("\(relPath):\(idx + 1) Memory crash hazard: '[unowned self]' used in asynchronous or network context. Use '[weak self]' instead.")
                }

                // 3. Delegate property declared without 'weak'
                if (trimmed.hasPrefix("var delegate:") || trimmed.hasPrefix("public var delegate:") || trimmed.hasPrefix("weak var delegate:")) && !trimmed.contains("weak ") {
                    findings.append("\(relPath):\(idx + 1) Retain cycle risk: Delegate property should be declared 'weak var delegate'.")
                }
            }
        }

        if findings.isEmpty {
            return .success("Memory Leak Scan passed: No retain cycles or strong self closure hazards detected across \(files.count) files in '\(path)'.")
        } else {
            return .success("Memory Leak Scan found \(findings.count) potential issues across \(files.count) files in '\(path)':\n\n" + findings.prefix(25).joined(separator: "\n") + (findings.count > 25 ? "\n...and \(findings.count - 25) more." : ""))
        }
    }
}
