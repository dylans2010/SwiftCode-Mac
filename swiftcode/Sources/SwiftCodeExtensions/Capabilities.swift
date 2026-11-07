import Foundation

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

    public var riskLevel: String {
        switch self {
        case .workspaceRead, .sourceControl: return "low"
        case .workspaceWrite, .build, .projectConfig, .assistTools, .webview: return "medium"
        case .outsideWorkspace, .network, .terminal, .process, .secrets: return "high"
        }
    }

    public var isGrantable: Bool { true }

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

    public var riskLevel: String {
        switch self {
        case .projectRead, .sourceControlRead, .docsSearch: return "low"
        case .workspaceRead, .uiContribute, .previewLive, .symbolsBrowse, .dictionaryOpen: return "medium"
        default: return "high"
        }
    }

    public var isGrantable: Bool { self != .assistInvoke }
}

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

public final class PermissionManager: @unchecked Sendable {
    public var promptHandler: (@Sendable (PermissionRequest) async -> Bool)?

    private let storage: ExtensionStorage?
    private let lock = NSLock()
    private var grants: [String: Set<ExtensionCapability>]

    public init(storage: ExtensionStorage = ExtensionStorage()) {
        self.storage = storage
        self.grants = Self.loadGrants(from: storage)
    }

    public init(grants: [String: Set<ExtensionCapability>]) {
        self.storage = nil
        self.grants = grants
    }

    private static func loadGrants(from storage: ExtensionStorage) -> [String: Set<ExtensionCapability>] {
        guard let data = try? Data(contentsOf: storage.grantsFile),
              let decoded = try? JSONDecoder().decode([String: [ExtensionCapability]].self, from: data) else {
            return [:]
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
            throw SwiftCodeExtensionError.permissionDenied(capability)
        }
    }

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
