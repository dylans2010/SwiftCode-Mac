import Foundation

// MARK: - Native plugins (spec §7.3)

public struct NativePluginManifest: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let commands: [ExtensionContributionCommand]
    public let capabilities: [ExtensionCapability]

    public init(id: String, name: String, version: String, description: String,
                commands: [ExtensionContributionCommand] = [], capabilities: [ExtensionCapability] = []) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.commands = commands
        self.capabilities = capabilities
    }

    /// Derived metadata: publisher `"swiftcode"`, kind `.native`.
    public var metadata: ExtensionMetadata {
        ExtensionMetadata(publisher: "swiftcode", name: id, version: version,
                          displayName: name, description: description, kind: .native)
    }
}

public struct NativePluginContext: Sendable {
    public let manifest: NativePluginManifest
    public let workspaceRoot: URL?
    public let workspace: WorkspaceBridge?
    public let permissions: PermissionManager
    public let registerCommand: @Sendable (String, @escaping @Sendable ([JSONValue]) async throws -> JSONValue) -> Void

    public init(manifest: NativePluginManifest, workspaceRoot: URL?, workspace: WorkspaceBridge?,
                permissions: PermissionManager,
                registerCommand: @escaping @Sendable (String, @escaping @Sendable ([JSONValue]) async throws -> JSONValue) -> Void) {
        self.manifest = manifest
        self.workspaceRoot = workspaceRoot
        self.workspace = workspace
        self.permissions = permissions
        self.registerCommand = registerCommand
    }
}

/// Trust boundary (stated plainly in Legacy, kept): plugins compiled
/// into the app run in-process and are trusted exactly as much as the
/// app itself. **Third-party native code is NOT loaded in-process** —
/// there is no dynamic bundle loading. Untrusted code ships as a VS
/// Code extension through the out-of-process host.
public protocol NativePlugin: Sendable {
    static var manifest: NativePluginManifest { get }
    init()
    func activate(context: NativePluginContext) async throws
    func deactivate() async
}

public extension NativePlugin {
    func deactivate() async {}
}

@MainActor
public final class NativePluginRegistry {
    public static let shared = NativePluginRegistry()

    private static let commandLock = NSLock()
    private static var commandTable: [String: @Sendable ([JSONValue]) async throws -> JSONValue] = [:]

    public static func registerCommand(_ id: String,
                                       handler: @escaping @Sendable ([JSONValue]) async throws -> JSONValue) {
        commandLock.lock(); defer { commandLock.unlock() }
        commandTable[id] = handler
    }

    public static func handler(for id: String) -> (@Sendable ([JSONValue]) async throws -> JSONValue)? {
        commandLock.lock(); defer { commandLock.unlock() }
        return commandTable[id]
    }

    public private(set) var manifests: [NativePluginManifest] = []
    private var instances: [any NativePlugin] = []

    public init() {}

    /// Dedupe by manifest; instantiates the plugin.
    public func register<Plugin: NativePlugin>(_ type: Plugin.Type) {
        guard !manifests.contains(where: { $0.id == Plugin.manifest.id }) else { return }
        manifests.append(Plugin.manifest)
        instances.append(type.init())
    }

    /// Activation failure per plugin is logged, never fatal.
    public func activateAll(workspaceRoot: URL?, workspace: WorkspaceBridge?,
                            permissions: PermissionManager) async {
        for (index, instance) in instances.enumerated() {
            let manifest = manifests[index]
            let context = NativePluginContext(
                manifest: manifest, workspaceRoot: workspaceRoot, workspace: workspace,
                permissions: permissions,
                registerCommand: { id, handler in Self.registerCommand(id, handler: handler) })
            do {
                try await instance.activate(context: context)
            } catch {
                DiagnosticsService.shared.error(
                    "Native plugin '\(manifest.id)' failed to activate: \(error.localizedDescription)",
                    extensionId: "swiftcode.\(manifest.id)")
            }
        }
    }

    public func executeCommand(_ command: String, args: [JSONValue] = []) async throws -> JSONValue {
        guard let handler = Self.handler(for: command) else {
            throw YcodeExtensionError.invalidRequest("Unknown native command '\(command)'.")
        }
        return try await handler(args)
    }

    public func contribution(for manifest: NativePluginManifest) -> ExtensionContribution {
        ExtensionContribution(
            commands: manifest.commands,
            outputLines: ["Native plugin '\(manifest.name)' v\(manifest.version) is active."])
    }
}

/// Sample plugin (spec §7.3): id `sample.workspace-lister`, one
/// command `extv2.sample.listWorkspace` listing up to 50 workspace
/// files (sorted), or "No workspace is open." / "Workspace is empty.".
/// The workspace check happens when the command runs, not at activation.
public struct SamplePlugin: NativePlugin {
    public static let manifest = NativePluginManifest(
        id: "sample.workspace-lister",
        name: "Workspace Lister (Sample)",
        version: "1.0.0",
        description: "Lists workspace files.",
        commands: [ExtensionContributionCommand(command: "extv2.sample.listWorkspace",
                                                title: "Sample: List Workspace Files")],
        capabilities: [.workspaceRead])

    public init() {}

    public func activate(context: NativePluginContext) async throws {
        context.registerCommand("extv2.sample.listWorkspace") { _ in
            guard let workspace = context.workspace else {
                return .string("No workspace is open.")
            }
            let files = try workspace.listFiles(extensionId: "swiftcode.sample.workspace-lister")
            let names = files.map { $0.relativePath }.sorted().prefix(50)
            guard !names.isEmpty else { return .string("Workspace is empty.") }
            return .string(names.joined(separator: "\n"))
        }
    }
}

// MARK: - Assist bridge (spec §7.1)

public struct AssistCapabilityDescriptor: Sendable {
    public let toolId: String
    public let name: String
    public let description: String
    public let parameters: [String: String]
    public let requiredParameters: [String]
    public let extensionId: String
    public let command: String
    public let requiredCapabilities: [ExtensionCapability]
    public let isReadOnly: Bool

    public init(toolId: String, name: String, description: String,
                parameters: [String: String] = [:], requiredParameters: [String] = [],
                extensionId: String, command: String,
                requiredCapabilities: [ExtensionCapability] = [], isReadOnly: Bool = true) {
        self.toolId = toolId
        self.name = name
        self.description = description
        self.parameters = parameters
        self.requiredParameters = requiredParameters
        self.extensionId = extensionId
        self.command = command
        self.requiredCapabilities = requiredCapabilities
        self.isReadOnly = isReadOnly
    }

    /// Missing required params and wrong primitive types
    /// (`string`/`number`/`boolean`) are caller errors, thrown before
    /// any execution. Unknown parameter types are ignored (no check).
    public func validate(input: [String: Any]) throws {
        for required in requiredParameters where input[required] == nil {
            throw YcodeExtensionError.invalidRequest("Missing required parameter '\(required)'.")
        }
        for (name, type) in parameters {
            guard let value = input[name] else { continue }
            switch type {
            case "string":
                guard value is String else {
                    throw YcodeExtensionError.invalidRequest("Parameter '\(name)' must be a string.")
                }
            case "number":
                guard value is NSNumber || value is Int || value is Double else {
                    throw YcodeExtensionError.invalidRequest("Parameter '\(name)' must be a number.")
                }
            case "boolean":
                guard value is Bool else {
                    throw YcodeExtensionError.invalidRequest("Parameter '\(name)' must be a boolean.")
                }
            default:
                break // Unknown parameter types are ignored.
            }
        }
    }
}

/// The only registration path: validated descriptors into the
/// existing tool registry — there is no parallel tool system. In Ycode
/// that means the MCP tool catalogue (`YcodeMCP`); this target only
/// builds and validates descriptors. Args are encoded as one JSON
/// object everywhere (deviation D-10: the Legacy `"key=value"` form
/// is not used).
public enum AssistBridge {
    /// `"extv2." + (extensionId + "." + command)` with every
    /// non-letter/digit/`.` character replaced by `_`.
    public static func toolId(for extensionId: String, command: String) -> String {
        let raw = "extv2.\(extensionId).\(command)"
        return raw.map { character in
            (character.isLetter || character.isNumber || character == ".") ? character : "_"
        }.reduce(into: "") { $0.append($1) }
    }

    /// Defaults: name = command title, description =
    /// `"Extension command '<command>' from <extensionId>."`,
    /// parameters empty, required empty, `isReadOnly: true`. Every
    /// extension command registers as a read-only tool with no
    /// parameters and no required capabilities unless the caller says
    /// otherwise.
    public static func descriptor(for command: ExtensionContributionCommand, extensionId: String,
                                  requiredCapabilities: [ExtensionCapability] = [],
                                  isReadOnly: Bool = true) -> AssistCapabilityDescriptor {
        AssistCapabilityDescriptor(
            toolId: toolId(for: extensionId, command: command.command),
            name: command.title,
            description: "Extension command '\(command.command)' from \(extensionId).",
            extensionId: extensionId, command: command.command,
            requiredCapabilities: requiredCapabilities, isReadOnly: isReadOnly)
    }

    /// Returns `false` (and logs a warning) when `.assistTools` is
    /// not granted — registration is a privileged act, not a default.
    @MainActor
    public static func register(_ descriptor: AssistCapabilityDescriptor,
                                permissions: PermissionManager) -> Bool {
        guard permissions.isGranted(extensionId: descriptor.extensionId, capability: .assistTools) else {
            DiagnosticsService.shared.warning(
                "Refused to register Assist tool '\(descriptor.toolId)': .assistTools is not granted.",
                extensionId: descriptor.extensionId)
            return false
        }
        return true
    }
}

// MARK: - Provider registry (spec §8.4)

/// Provider registrations the editor consults
/// (completion/hover/diagnostics only). Definition/reference/
/// formatting/code-action providers have no registry storage at all.
public struct ExtensionDiagnostic: Codable, Hashable, Sendable {
    public let relativePath: String
    public let range: TextRange
    public let message: String
    public let severity: String
    public let source: String

    public init(relativePath: String, range: TextRange, message: String,
                severity: String = "Error", source: String) {
        self.relativePath = relativePath
        self.range = range
        self.message = message
        self.severity = severity
        self.source = source
    }
}

@MainActor
public final class ProviderRegistry {
    public static let shared = ProviderRegistry()

    public private(set) var diagnostics: [String: [ExtensionDiagnostic]] = [:]
    public private(set) var completionProviders: [String: String] = [:]
    public private(set) var hoverProviders: [String: String] = [:]

    public init() {}

    /// Replaces the whole list for a path (cross-extension overwrite:
    /// a second extension publishing for the same path replaces the
    /// first's diagnostics — observed behaviour, D-13).
    public func publishDiagnostics(extensionId: String, relativePath: String,
                                   diagnostics: [ExtensionDiagnostic]) {
        self.diagnostics[relativePath] = diagnostics
    }

    /// Last registration wins per language.
    public func registerCompletionProvider(extensionId: String, language: String) {
        completionProviders[language] = extensionId
    }

    public func registerHoverProvider(extensionId: String, language: String) {
        hoverProviders[language] = extensionId
    }

    public func clear(for extensionId: String) {
        diagnostics = diagnostics.mapValues { entries in
            entries.filter { $0.source != extensionId }
        }.filter { !$0.value.isEmpty }
        completionProviders = completionProviders.filter { $0.value != extensionId }
        hoverProviders = hoverProviders.filter { $0.value != extensionId }
    }
}
