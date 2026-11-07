import Foundation
import SwiftCodeAssistant
import SwiftCodeExtensions

public struct ExtV2AssistCapability: Sendable {
    public let toolId: String
    public let name: String
    public let description: String
    public let parameters: [String: String]
    public let requiredParameters: [String]
    public let extensionId: String
    public let command: String
    public let requiredCapabilities: [ExtensionCapability]
    public let isReadOnly: Bool

    public init(
        toolId: String, name: String, description: String,
        parameters: [String: String] = [:], requiredParameters: [String] = [],
        extensionId: String, command: String,
        requiredCapabilities: [ExtensionCapability] = [], isReadOnly: Bool = true
    ) {
        self.toolId = toolId; self.name = name; self.description = description
        self.parameters = parameters; self.requiredParameters = requiredParameters
        self.extensionId = extensionId; self.command = command
        self.requiredCapabilities = requiredCapabilities; self.isReadOnly = isReadOnly
    }

    public init(descriptor: AssistCapabilityDescriptor) {
        self.init(toolId: descriptor.toolId, name: descriptor.name, description: descriptor.description,
                  parameters: descriptor.parameters, requiredParameters: descriptor.requiredParameters,
                  extensionId: descriptor.extensionId, command: descriptor.command,
                  requiredCapabilities: descriptor.requiredCapabilities, isReadOnly: descriptor.isReadOnly)
    }

    public func validate(input: [String: Any]) throws {
        for required in requiredParameters {
            guard input[required] != nil else {
                throw SwiftCodeExtensionError.invalidRequest("Missing required parameter: \(required)")
            }
        }
        for (key, type) in parameters {
            guard let value = input[key] else { continue }
            switch type {
            case "string": guard value is String else { throw SwiftCodeExtensionError.invalidRequest("Parameter '\(key)' must be a string.") }
            case "number": guard value is NSNumber || value is Int || value is Double else { throw SwiftCodeExtensionError.invalidRequest("Parameter '\(key)' must be a number.") }
            case "boolean": guard value is Bool else { throw SwiftCodeExtensionError.invalidRequest("Parameter '\(key)' must be a boolean.") }
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
        for command: ExtensionContributionCommand, extensionId: String,
        requiredCapabilities: [ExtensionCapability] = [], isReadOnly: Bool = true
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
        permissions: PermissionManager
    ) -> Bool {
        guard permissions.isGranted(extensionId: descriptor.extensionId, capability: .assistTools) else {
            DiagnosticsService.shared.warning(
                "Assist registration skipped: '.assistTools' capability not granted.",
                extensionId: descriptor.extensionId)
            return false
        }
        AssistToolRegistry.shared.register(ExtV2ExtensionAssistTool(descriptor: descriptor))
        return true
    }

    @MainActor
    public static func installRegistrationHandler() {
        AssistBridge.registrationHandler = { descriptor, permissions in
            register(ExtV2AssistCapability(descriptor: descriptor), permissions: permissions)
        }
    }
}

@MainActor
public final class ExtV2AssistExecution {
    public static let shared = ExtV2AssistExecution()

    private init() {}

    public func execute(descriptor: ExtV2AssistCapability, input: [String: Any]) async throws -> String {
        try descriptor.validate(input: input)
        for capability in descriptor.requiredCapabilities {
            try ExtensionManager.shared.permissions.check(extensionId: descriptor.extensionId, capability: capability)
        }
        let args = input.map { key, value in SwiftCodeExtensions.JSONValue.string("\(key)=\(value)") }
        return try await ExtensionManager.shared.executeCommand(
            extensionId: descriptor.extensionId, command: descriptor.command, args: args)
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
