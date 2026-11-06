import Foundation

// MARK: - v2 capabilities (spec §5.1, 12 values)

public enum ExtensionCapability: String, Codable, Sendable, CaseIterable {
    case workspaceRead
    case workspaceWrite
    case outsideWorkspace
    case network
    case terminal
    case process
    case secrets
    case sourceControl
    case build
    case assistTools
    case projectConfig
    case webview

    public var displayName: String {
        switch self {
        case .workspaceRead: return "Read workspace files"
        case .workspaceWrite: return "Write workspace files"
        case .outsideWorkspace: return "Access files outside the workspace"
        case .network: return "Network access"
        case .terminal: return "Run terminal commands"
        case .process: return "Launch processes"
        case .secrets: return "Read stored secrets"
        case .sourceControl: return "Source-control operations"
        case .build: return "Build and test execution"
        case .assistTools: return "Register Assist tools"
        case .projectConfig: return "Change project configuration"
        case .webview: return "Show webviews"
        }
    }

    /// Maps an SDK capability id to the v2 runtime capabilities that
    /// enforce it (spec §5.3, a Ycode decision — Legacy never maps them).
    public static func v2Capabilities(for sdkCapability: SDKCapabilityID) -> [ExtensionCapability] {
        switch sdkCapability {
        case .workspaceRead, .projectRead, .sourceControlRead, .docsSearch, .symbolsBrowse, .dictionaryOpen:
            return [.workspaceRead]
        case .workspaceWrite, .sourceControlWrite:
            return [.workspaceWrite]
        case .networkRequest:
            return [.network]
        case .terminalSandbox, .taskExecute:
            return [.terminal, .process]
        case .buildExecute:
            return [.build]
        case .credentialsUse, .useSecurity, .securityAddValue, .securityHasValue,
             .securityListValueIDs, .securityDeleteValue, .securityUseValue:
            return [.secrets]
        case .assistInvoke, .assistUI, .assistHeadless, .assistMainView:
            return [.assistTools]
        case .uiContribute, .previewLive, .uiBuilderOpen, .simulatorView, .sandboxView,
             .virtualizationView, .deployConsoleView, .dbExploreView, .ciVisualWF,
             .deviceConnectOpen, .useSwiftCodeModel:
            return [.webview]
        }
    }
}

// MARK: - SDK capabilities (spec §5.1, 34 ids verbatim)

public enum SDKCapabilityID: String, Codable, Sendable, CaseIterable {
    case projectRead = "project.read"
    case workspaceRead = "workspace.read"
    case workspaceWrite = "workspace.write"
    case sourceControlRead = "source-control.read"
    case sourceControlWrite = "source-control.write"
    case buildExecute = "build.execute"
    case taskExecute = "task.execute"
    case networkRequest = "network.request"
    case uiContribute = "ui.contribute"
    case credentialsUse = "credentials.use"
    case useSecurity = "use.Security"
    case assistInvoke = "assist.invoke"
    case assistUI = "assist.ui"
    case assistHeadless = "assist.headless"
    case assistMainView = "assist.main"
    case dbExploreView = "db.ExploreView"
    case ciVisualWF = "ci.VisualWF"
    case sandboxView = "sandbox.view"
    case virtualizationView = "virtualization.view"
    case deployConsoleView = "deployConsole.view"
    case useSwiftCodeModel = "use.SwiftCodeModel"
    case terminalSandbox = "terminal.sandbox"
    case simulatorView = "simulator.view"
    case previewLive = "preview.live"
    case uiBuilderOpen = "uibuilder.open"
    case symbolsBrowse = "symbols.browse"
    case docsSearch = "docs.search"
    case dictionaryOpen = "dictionary.open"
    case deviceConnectOpen = "deviceconnect.open"
    case securityAddValue = "security.addValue"
    case securityHasValue = "security.hasValue"
    case securityListValueIDs = "security.listValueIDs"
    case securityDeleteValue = "security.deleteValue"
    case securityUseValue = "security.useValue"

    /// Risk levels from `ExtensionCapabilityID.riskLevel`.
    public var riskLevel: String {
        switch self {
        case .projectRead, .sourceControlRead, .docsSearch: return "low"
        case .workspaceRead, .uiContribute, .previewLive, .symbolsBrowse, .dictionaryOpen: return "medium"
        default: return "high"
        }
    }

    /// `assist.invoke` is restricted deny-by-default; every other id is grantable.
    public var isGrantable: Bool { self != .assistInvoke }
}

// MARK: - Permissions (spec §5.2)

public struct PermissionRequest: Sendable {
    public let extensionId: String
    public let capability: ExtensionCapability
    public let reason: String

    public init(extensionId: String, capability: ExtensionCapability, reason: String) {
        self.extensionId = extensionId
        self.capability = capability
        self.reason = reason
    }
}

/// Deny-by-default grant store over `grants.json`
/// (`{extensionId: [capability-rawValue]}`). Revocation takes effect
/// on the next call. The grants file is written with mode `0600`
/// (adopted from the SDK grant store, deviation D-2).
public final class PermissionManager: @unchecked Sendable {
    public var promptHandler: (@Sendable (PermissionRequest) async -> Bool)?

    private let storage: ExtensionStorage?
    private let lock = NSLock()
    private var grants: [String: Set<ExtensionCapability>]

    public init(storage: ExtensionStorage = ExtensionStorage()) {
        self.storage = storage
        self.grants = Self.loadGrants(from: storage)
    }

    /// Test variant: in-memory grants only, no file backing.
    public init(grants: [String: Set<ExtensionCapability>]) {
        self.storage = nil
        self.grants = grants
    }

    private static func loadGrants(from storage: ExtensionStorage) -> [String: Set<ExtensionCapability>] {
        guard let data = try? Data(contentsOf: storage.grantsFile),
              let decoded = try? JSONDecoder().decode([String: [ExtensionCapability]].self, from: data) else {
            return [:] // Unparseable -> empty, not fatal.
        }
        return decoded.mapValues { Set($0) }
    }

    private func persistLocked() {
        guard let storage else { return }
        let snapshot = grants.mapValues { Array($0).sorted(by: { $0.rawValue < $1.rawValue }) }
        do {
            try storage.writeAtomically(snapshot, to: storage.grantsFile)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: storage.grantsFile.path)
        } catch {
            DiagnosticsService.shared.error("Could not persist grants: \(error.localizedDescription)")
        }
    }

    public func isGranted(extensionId: String, capability: ExtensionCapability) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return grants[extensionId]?.contains(capability) ?? false
    }

    public func grantedCapabilities(for extensionId: String) -> [ExtensionCapability] {
        lock.lock(); defer { lock.unlock() }
        return Array(grants[extensionId] ?? []).sorted(by: { $0.rawValue < $1.rawValue })
    }

    public func check(extensionId: String, capability: ExtensionCapability) throws {
        guard isGranted(extensionId: extensionId, capability: capability) else {
            throw YcodeExtensionError.permissionDenied(capability)
        }
    }

    /// Already granted → `true` immediately. No `promptHandler`
    /// installed → `false` (a headless call is a denial, not a queue).
    public func request(extensionId: String, capability: ExtensionCapability, reason: String) async -> Bool {
        if isGranted(extensionId: extensionId, capability: capability) { return true }
        guard let promptHandler else { return false }
        let approved = await promptHandler(PermissionRequest(extensionId: extensionId,
                                                             capability: capability, reason: reason))
        if approved { grant(extensionId: extensionId, capability: capability) }
        return approved
    }

    public func grant(extensionId: String, capability: ExtensionCapability) {
        lock.lock(); defer { lock.unlock() }
        grants[extensionId, default: []].insert(capability)
        persistLocked()
    }

    public func revoke(extensionId: String, capability: ExtensionCapability) {
        lock.lock(); defer { lock.unlock() }
        grants[extensionId]?.remove(capability)
        persistLocked()
    }

    public func revokeAll(for extensionId: String) {
        lock.lock(); defer { lock.unlock() }
        grants.removeValue(forKey: extensionId)
        persistLocked()
    }
}
