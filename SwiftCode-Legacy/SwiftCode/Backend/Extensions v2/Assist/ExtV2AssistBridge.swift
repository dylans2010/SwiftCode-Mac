import Foundation

public struct ExtV2AssistCapability: Sendable {
    public let toolId: String
    public let name: String
    public let description: String
    public let parameters: [String: String]
    public let requiredParameters: [String]
    public let extensionId: String
    public let command: String
    public let requiredCapabilities: [ExtV2Capability]
    public let isReadOnly: Bool

    public init(
        toolId: String, name: String, description: String,
        parameters: [String: String] = [:], requiredParameters: [String] = [],
        extensionId: String, command: String,
        requiredCapabilities: [ExtV2Capability] = [], isReadOnly: Bool = true
    ) {
        self.toolId = toolId; self.name = name; self.description = description
        self.parameters = parameters; self.requiredParameters = requiredParameters
        self.extensionId = extensionId; self.command = command
        self.requiredCapabilities = requiredCapabilities; self.isReadOnly = isReadOnly
    }

    public func validate(input: [String: Any]) throws {
        for required in requiredParameters {
            guard input[required] != nil else {
                throw ExtV2Error.invalidRequest("Missing required parameter: \(required)")
            }
        }
        for (key, type) in parameters {
            guard let value = input[key] else { continue }
            switch type {
            case "string": guard value is String else { throw ExtV2Error.invalidRequest("Parameter '\(key)' must be a string.") }
            case "number": guard value is NSNumber || value is Int || value is Double else { throw ExtV2Error.invalidRequest("Parameter '\(key)' must be a number.") }
            case "boolean": guard value is Bool else { throw ExtV2Error.invalidRequest("Parameter '\(key)' must be a boolean.") }
            default: break
            }
        }
    }
}

public enum ExtV2AssistBridge {
    public static func toolId(for extensionId: String, command: String) -> String {
        let sanitized = (extensionId + "." + command)
            .map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : Character("_") }
        return "extv2." + String(sanitized)
    }

    public static func descriptor(
        for command: ExtV2ContributionCommand, extensionId: String,
        requiredCapabilities: [ExtV2Capability] = [], isReadOnly: Bool = true
    ) -> ExtV2AssistCapability {
        ExtV2AssistCapability(
            toolId: toolId(for: extensionId, command: command.command),
            name: command.title, description: "Extension command '\(command.command)' from \(extensionId).",
            extensionId: extensionId, command: command.command,
            requiredCapabilities: requiredCapabilities, isReadOnly: isReadOnly)
    }

    @MainActor
    public static func register(
        _ descriptor: ExtV2AssistCapability,
        permissions: ExtV2PermissionManager
    ) -> Bool {
        guard permissions.isGranted(extensionId: descriptor.extensionId, capability: .assistTools) else {
            ExtV2DiagnosticsService.shared.warning(
                "Assist registration skipped: '.assistTools' capability not granted.",
                extensionId: descriptor.extensionId)
            return false
        }
        AssistToolRegistry.shared.register(ExtV2ExtensionAssistTool(descriptor: descriptor))
        return true
    }
}

@MainActor
public final class ExtV2AssistExecution {
    public static let shared = ExtV2AssistExecution()
    public var hostManager: ExtV2HostManager?
    public var permissions: ExtV2PermissionManager?

    private init() {}

    public func execute(descriptor: ExtV2AssistCapability, input: [String: Any]) async throws -> String {
        try descriptor.validate(input: input)
        if let permissions {
            for capability in descriptor.requiredCapabilities {
                try permissions.check(extensionId: descriptor.extensionId, capability: capability)
            }
        }
        if ExtV2NativePluginRegistry.handler(for: descriptor.command) != nil {
            let nativeResult = try await ExtV2NativePluginRegistry.shared.executeCommand(
                descriptor.command,
                args: input.map { key, value in ExtV2JSONValue.string("\(key)=\(value)") })
            return nativeResult.stringValue ?? ""
        }
        guard let host = hostManager else {
            throw ExtV2Error.host("No extension host is available for tool '\(descriptor.toolId)'.")
        }
        let args = input.map { key, value in ExtV2JSONValue.string("\(key)=\(value)") }
        let result = try await host.executeCommand(extensionId: descriptor.extensionId, command: descriptor.command, args: args)
        return result.stringValue ?? ""
    }
}

public struct ExtV2ExtensionAssistTool: AssistTool {
    public let descriptor: ExtV2AssistCapability

    public var id: String { descriptor.toolId }
    public var name: String { descriptor.name }
    public var description: String { descriptor.description }
    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { descriptor.isReadOnly ? .safeRead : .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: descriptor.description,
            properties: Dictionary(uniqueKeysWithValues: descriptor.parameters.map { key, type in
                (key, JSONSchema(type: type, description: "Parameter '\(key)'."))
            }),
            required: descriptor.requiredParameters
        )
    }

    public init(descriptor: ExtV2AssistCapability) {
        self.descriptor = descriptor
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let output = try await ExtV2AssistExecution.shared.execute(descriptor: descriptor, input: input)
            return .success(output, data: ["toolId": descriptor.toolId, "extensionId": descriptor.extensionId])
        } catch {
            return .failure("Extension tool '\(descriptor.toolId)' failed: \(error.localizedDescription)")
        }
    }
}
