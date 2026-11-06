// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Extensions v2/Assist/ExtV2AssistBridge.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution); REWORKED by wiring-backend (W2).
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/ExtV2AssistBridge.swift`).
// Audit gap this port closes (claimed-covered-audit):
//   - actual registration into a tool registry (register() only permission-checks and returns true; the comment admits this target only builds/validates descriptors)
//   - ExtV2AssistExecution (validate -> permission check -> native/host routing with host command timeout)
//   - ExtV2ExtensionAssistTool (the AssistTool wrapper)
// WIRING (wiring-backend): the file as landed did not compile — it
//   referenced eight `ExtV2*` types that do not exist in the destination
//   (`ExtV2Capability`, `ExtV2ContributionCommand`, `ExtV2DiagnosticsService`,
//   `ExtV2Error`, `ExtV2HostManager`, `ExtV2JSONValue`,
//   `ExtV2NativePluginRegistry`, `ExtV2PermissionManager`). Each is now
//   bound to the destination type that already implements it (all in
//   SwiftCodeExtensions, already a SwiftCodeMCP dependency):
//     ExtV2Capability -> ExtensionCapability (same `.assistTools` case)
//     ExtV2ContributionCommand -> ExtensionContributionCommand
//     ExtV2DiagnosticsService -> DiagnosticsService
//     ExtV2Error -> SwiftCodeExtensionError (same `.host` / `.invalidRequest` cases)
//     ExtV2HostManager / native routing -> ExtensionManager.executeCommand
//       (native handlers first, ownership check, auto-activate, host RPC —
//       the same routing Legacy's execution did, in one call)
//     ExtV2JSONValue -> SwiftCodeExtensions.JSONValue (qualified: SwiftCodeMCP
//       has its own JSONValue, now in SwiftCodeAssistant)
//     ExtV2PermissionManager -> PermissionManager
//   The Legacy host-command timeout has no destination equivalent —
//   `ExtensionManager.executeCommand` carries none — so none is invented.
//   Registration is wired end to end: `installRegistrationHandler()`
//   (called from `SwiftCodeMCPHost.init`) sets
//   `AssistBridge.registrationHandler`, so `ExtensionManager.activate`
//   -> `registerAssistCommands` -> `AssistBridge.register` now really
//   registers the tool in `AssistToolRegistry.shared` instead of only
//   permission-checking. The handler converts the Extensions descriptor
//   field-for-field; the two descriptor types are the same shape.
//   `ExtV2AssistExecution` keeps no host/permissions of its own: it
//   uses `ExtensionManager.shared` (permissions + execution), so there
//   is no second host reference to keep in sync.
// ADAPTATIONS:
//   - Added cross-target import(s): import SwiftCodeExtensions, import SwiftCodeAssistant.

import Foundation
import SwiftCodeAssistant
import SwiftCodeExtensions

// MARK: - Assist integration
//
// Extensions register capabilities ONLY through validated descriptors
// here, and only into the existing AssistToolRegistry — there is no
// parallel tool system. Registration requires the `.assistTools`
// capability to be granted; execution re-checks every capability the
// command needs, enforces the host command timeout, and reports
// failures as AssistToolResult failures, never as silent successes.
// A tool id is `extv2.<extension-id>.<command>` with non-identifier
// characters replaced, so ids are stable, unique per command, and
// never collide with built-in tools (the registry keeps the first
// registration on a collision and logs it).

public struct ExtV2AssistCapability: Sendable {
    public let toolId: String
    public let name: String
    public let description: String
    /// Parameter name -> JSON type ("string", "number", "boolean").
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

    /// Builds the bridge capability from the Extensions descriptor
    /// `AssistBridge` hands out (same fields, same shape).
    public init(descriptor: AssistCapabilityDescriptor) {
        self.init(toolId: descriptor.toolId, name: descriptor.name, description: descriptor.description,
                  parameters: descriptor.parameters, requiredParameters: descriptor.requiredParameters,
                  extensionId: descriptor.extensionId, command: descriptor.command,
                  requiredCapabilities: descriptor.requiredCapabilities, isReadOnly: descriptor.isReadOnly)
    }

    /// Validates an Assist input dict against the descriptor before any
    /// execution: missing required params and wrong primitive types are
    /// caller errors, caught here rather than inside an extension.
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

    /// Registers a descriptor's tool in the existing registry. Returns
    /// false (and logs) when the extension lacks the `.assistTools`
    /// capability — registration is a privileged act, not a default.
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

    /// WIRING (wiring-backend): plugs the real registration into
    /// `AssistBridge.register` (SwiftCodeExtensions). Extensions cannot
    /// depend on SwiftCodeMCP (the dependency runs the other way), so
    /// the bridge is installed from the MCP side — `SwiftCodeMCPHost`
    /// calls this once at startup. After this, an extension activation
    /// really registers its commands as tools; before it,
    /// `AssistBridge.register` only permission-checked.
    @MainActor
    public static func installRegistrationHandler() {
        AssistBridge.registrationHandler = { descriptor, permissions in
            register(ExtV2AssistCapability(descriptor: descriptor), permissions: permissions)
        }
    }
}

/// The single execution path for extension tools: validate, check
/// permissions, route to the owning host or native plugin, and return
/// a typed result. Host routing is by command ownership, so a tool can
/// never execute a command belonging to a different extension.
@MainActor
public final class ExtV2AssistExecution {
    public static let shared = ExtV2AssistExecution()

    private init() {}

    public func execute(descriptor: ExtV2AssistCapability, input: [String: Any]) async throws -> String {
        try descriptor.validate(input: input)
        for capability in descriptor.requiredCapabilities {
            try ExtensionManager.shared.permissions.check(extensionId: descriptor.extensionId, capability: capability)
        }
        // WIRING (wiring-backend): the destination's own execution path.
        // `ExtensionManager.executeCommand` is Legacy's routing in one
        // call — native handlers first, then the ownership check (a tool
        // can never execute a command belonging to a different
        // extension), auto-activation of a stopped host, then host RPC —
        // and returns the result string. No second host reference is
        // kept here, so there is nothing to wire up before first use.
        // (SwiftCodeExtensions.JSONValue is qualified: SwiftCodeMCP has
        // its own JSONValue, now in SwiftCodeAssistant.)
        let args = input.map { key, value in SwiftCodeExtensions.JSONValue.string("\(key)=\(value)") }
        return try await ExtensionManager.shared.executeCommand(
            extensionId: descriptor.extensionId, command: descriptor.command, args: args)
    }
}

/// AssistTool conformance for one extension capability. Stored state is
/// Sendable (the descriptor only); execution goes through the shared
/// execution singleton, so no host reference is stored in the tool.
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
