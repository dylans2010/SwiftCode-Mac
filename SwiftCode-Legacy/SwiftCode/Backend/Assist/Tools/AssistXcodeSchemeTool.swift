import Foundation

public struct AssistXcodeSchemeTool: AssistTool {
    public let id = "xcode_scheme_manager"
    public let name = "Xcode Scheme & Build Configuration Manager"
    public let description = "Inspects, lists, and queries Xcode schemes, targets, and build configurations in the workspace."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "List and inspect Xcode schemes, build targets, and configurations.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action: 'list_schemes', 'inspect_scheme'."),
                "schemeName": JSONSchema(type: "string", description: "Scheme name to inspect (for 'inspect_scheme').")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }

        switch action.lowercased() {
        case "list_schemes", "list":
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.currentDirectoryURL = context.workspaceRoot
            process.arguments = ["-list"]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    return .success("Xcode Schemes & Targets:\n\(stdout)")
                } else {
                    return .failure("Failed to list Xcode schemes:\n\(stdout)")
                }
            } catch {
                return .failure("Error executing xcodebuild -list: \(error.localizedDescription)")
            }

        case "inspect_scheme":
            guard let schemeName = input["schemeName"] as? String, !schemeName.isEmpty else {
                return .failure("schemeName parameter is required for inspect_scheme")
            }

            // Search for scheme file in workspace
            let fileManager = FileManager.default
            if let enumerator = fileManager.enumerator(at: context.workspaceRoot, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.lastPathComponent == "\(schemeName).xcscheme" {
                        if let xmlContent = try? String(contentsOf: fileURL, encoding: .utf8) {
                            return .success("Scheme '\(schemeName)' found at \(fileURL.lastPathComponent):\n\n\(xmlContent.prefix(2000))")
                        }
                    }
                }
            }
            return .failure("Scheme file '\(schemeName).xcscheme' not found in workspace.")

        default:
            return .failure("Unsupported action '\(action)'. Valid: list_schemes, inspect_scheme")
        }
    }
}
