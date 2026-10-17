import Foundation

public struct AssistSwiftPackageTool: AssistTool {
    public let id = "swift_package_manager"
    public let name = "Swift Package Manager"
    public let description = "Inspects, resolves, updates, and validates Swift Package Manager (SPM) dependencies."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Interact with Swift Package Manager (Package.swift) in the active workspace.",
            properties: [
                "action": JSONSchema(type: "string", description: "Action to perform: 'resolve', 'update', 'status', 'dump_manifest', 'describe'."),
                "packageDir": JSONSchema(type: "string", description: "Workspace-relative directory containing Package.swift (defaults to workspace root).")
            ],
            required: ["action"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let action = input["action"] as? String else {
            return .failure("Missing required parameter: action")
        }

        let packageDir = (input["packageDir"] as? String) ?? ""
        let targetDir = packageDir.isEmpty ? context.workspaceRoot : context.workspaceRoot.appendingPathComponent(packageDir)

        let packageSwiftPath = targetDir.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: packageSwiftPath.path) else {
            return .failure("Package.swift not found at \(packageSwiftPath.path)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.currentDirectoryURL = targetDir

        var arguments = ["package"]
        switch action.lowercased() {
        case "resolve":
            arguments.append("resolve")
        case "update":
            arguments.append("update")
        case "status":
            arguments.append("status")
        case "dump_manifest":
            arguments.append("dump-package")
        case "describe":
            arguments.append("describe")
        default:
            return .failure("Unsupported action '\(action)'. Valid: resolve, update, status, dump_manifest, describe")
        }

        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outData, encoding: .utf8) ?? ""
            let stderr = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                let result = stdout.isEmpty ? "SPM \(action) completed successfully." : stdout
                return .success(result)
            } else {
                return .failure("SPM \(action) failed with code \(process.terminationStatus):\n\(stderr)\n\(stdout)")
            }
        } catch {
            return .failure("Failed to execute swift package: \(error.localizedDescription)")
        }
    }
}
