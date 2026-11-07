import Foundation

public struct ExtV2NativePluginManifest: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let commands: [ExtV2ContributionCommand]
    public let capabilities: [ExtV2Capability]

    public init(id: String, name: String, version: String, description: String,
                commands: [ExtV2ContributionCommand] = [], capabilities: [ExtV2Capability] = []) {
        self.id = id; self.name = name; self.version = version
        self.description = description; self.commands = commands; self.capabilities = capabilities
    }

    public var metadata: ExtV2ExtensionMetadata {
        ExtV2ExtensionMetadata(
            publisher: "swiftcode", name: id, version: version,
            displayName: name, description: description, kind: .native)
    }
}

public struct ExtV2NativePluginContext: Sendable {
    public let manifest: ExtV2NativePluginManifest
    public let workspaceRoot: URL?
    public let workspace: ExtV2WorkspaceBridge?
    public let permissions: ExtV2PermissionManager
    public let registerCommand: @Sendable (String, @escaping @Sendable ([ExtV2JSONValue]) async throws -> ExtV2JSONValue) -> Void

    public init(
        manifest: ExtV2NativePluginManifest, workspaceRoot: URL?,
        workspace: ExtV2WorkspaceBridge?, permissions: ExtV2PermissionManager,
        registerCommand: @escaping @Sendable (String, @escaping @Sendable ([ExtV2JSONValue]) async throws -> ExtV2JSONValue) -> Void
    ) {
        self.manifest = manifest; self.workspaceRoot = workspaceRoot
        self.workspace = workspace; self.permissions = permissions
        self.registerCommand = registerCommand
    }
}

public protocol ExtV2NativePlugin: Sendable {
    static var manifest: ExtV2NativePluginManifest { get }
    init()
    func activate(context: ExtV2NativePluginContext) async throws
    func deactivate() async
}

public extension ExtV2NativePlugin {
    func deactivate() async {}
}

@MainActor
public final class ExtV2NativePluginRegistry: ObservableObject {
    public static let shared = ExtV2NativePluginRegistry()

    nonisolated private static let commandLock = NSLock()
    nonisolated(unsafe) private static var commandTable: [String: @Sendable ([ExtV2JSONValue]) async throws -> ExtV2JSONValue] = [:]

    nonisolated public static func registerCommand(_ id: String, handler: @escaping @Sendable ([ExtV2JSONValue]) async throws -> ExtV2JSONValue) {
        commandLock.lock(); defer { commandLock.unlock() }
        commandTable[id] = handler
    }

    nonisolated public static func handler(for id: String) -> (@Sendable ([ExtV2JSONValue]) async throws -> ExtV2JSONValue)? {
        commandLock.lock(); defer { commandLock.unlock() }
        return commandTable[id]
    }

    @Published public private(set) var manifests: [ExtV2NativePluginManifest] = []
    private var activePlugins: [String: any ExtV2NativePlugin] = [:]

    public init() {}

    public func register<Plugin: ExtV2NativePlugin>(_ type: Plugin.Type) {
        let manifest = Plugin.manifest
        if !manifests.contains(manifest) { manifests.append(manifest) }
        activePlugins[manifest.id] = Plugin()
    }

    public func activateAll(workspaceRoot: URL?, workspace: ExtV2WorkspaceBridge?, permissions: ExtV2PermissionManager) async {
        for (id, plugin) in activePlugins {
            guard let manifest = manifests.first(where: { $0.id == id }) else { continue }
            let context = ExtV2NativePluginContext(
                manifest: manifest, workspaceRoot: workspaceRoot, workspace: workspace,
                permissions: permissions,
                registerCommand: { commandId, handler in
                    ExtV2NativePluginRegistry.registerCommand(commandId, handler: handler)
                })
            do {
                try await plugin.activate(context: context)
                ExtV2DiagnosticsService.shared.info("Native plugin activated.", extensionId: id)
            } catch {
                ExtV2DiagnosticsService.shared.error("Native plugin activation failed: \(error.localizedDescription)", extensionId: id)
            }
        }
    }

    public func executeCommand(_ command: String, args: [ExtV2JSONValue] = []) async throws -> ExtV2JSONValue {
        guard let handler = Self.handler(for: command) else {
            throw ExtV2Error.invalidRequest("No native plugin command '\(command)' is registered.")
        }
        return try await handler(args)
    }

    public func contribution(for manifest: ExtV2NativePluginManifest) -> ExtV2Contribution {
        ExtV2Contribution(
            commands: manifest.commands,
            views: [],
            treeItems: [],
            statusBarText: nil,
            outputLines: ["Native plugin '\(manifest.name)' v\(manifest.version) is active."])
    }
}
