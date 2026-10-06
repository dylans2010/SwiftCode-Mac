import Foundation

public struct AssistEnvironmentInfoTool: AssistTool {
    public let id = "env_info"
    public let name = "Environment Info"
    public let description = "Provides information about the runtime environment (OS, Swift version, etc.)."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Provides information about runtime environment and system capabilities.",
            properties: [
                "includeHardware": JSONSchema(type: "boolean", description: "Whether to include detailed host hardware specs.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let processInfo = ProcessInfo.processInfo
        let locale = Locale.current.identifier
        let tz = TimeZone.current.identifier
        let env = [
            "os": processInfo.operatingSystemVersionString,
            "locale": locale,
            "timezone": tz,
            "cpu_count": "\(processInfo.processorCount)",
            "physical_memory_bytes": "\(processInfo.physicalMemory)",
            "workspace_root": context.workspaceRoot.path
        ]
        return .success("Environment info retrieved", data: env)
    }
}
