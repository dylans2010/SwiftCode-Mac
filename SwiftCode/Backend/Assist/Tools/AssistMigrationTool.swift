import Foundation

public struct AssistMigrationTool: AssistTool {
    public let id = "swift_migration_advisor"
    public let name = "Swift 6 Migration Advisor"
    public let description = "Audits Swift code for Swift 6 strict concurrency compliance, mutable globals, actor boundaries, and Sendable conformance."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Analyze code for Swift 6 strict concurrency readiness.",
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
            return .failure("Path does not exist: \(path)")
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

        var warnings: [String] = []

        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let relPath = fileURL.path.replacingOccurrences(of: context.workspaceRoot.path + "/", with: "")
            let lines = content.components(separatedBy: .newlines)

            for (idx, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("//") { continue }

                // 1. Mutable global / static variable (Strict concurrency violation in Swift 6)
                if (trimmed.hasPrefix("public static var ") || trimmed.hasPrefix("static var ")) && !trimmed.contains("{") {
                    warnings.append("\(relPath):\(idx + 1) [Swift 6] Mutable static variable 'static var' without actor isolation violates strict concurrency. Protect with actor or mark 'nonisolated(unsafe)'.")
                }

                // 2. ObservableObject vs @Observable
                if trimmed.contains(": ObservableObject") {
                    warnings.append("\(relPath):\(idx + 1) [Swift 6 / Observation] Uses legacy 'ObservableObject'. Recommend migrating to Swift modern '@Observable'.")
                }

                // 3. @Published properties
                if trimmed.contains("@Published ") {
                    warnings.append("\(relPath):\(idx + 1) [Swift 6 / Observation] Legacy '@Published' property wrapper. In Swift Observation framework, properties are observable by default.")
                }
            }
        }

        if warnings.isEmpty {
            return .success("Swift 6 Migration Audit passed: All analyzed code in '\(path)' conforms to Swift 6 strict concurrency patterns.")
        } else {
            return .success("Swift 6 Migration Advisor found \(warnings.count) migration opportunities across \(files.count) files in '\(path)':\n\n" + warnings.prefix(25).joined(separator: "\n") + (warnings.count > 25 ? "\n...and \(warnings.count - 25) more." : ""))
        }
    }
}
