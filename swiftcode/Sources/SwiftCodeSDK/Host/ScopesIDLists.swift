import Foundation
import SwiftCodeExtensions

// MARK: - ScopesIDLists
//
// Ported from Legacy `SwiftCode/SDK/Host/ScopesIDLists.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The fixed scope list: every capability an extension can request,
// whether it opens a view or calls an API. 32 entries — NOT 35:
// `use.Security` and `assist.main` are umbrella/entitlement surfaces,
// not separately requestable scopes. Keep this list in sync with the
// TypeScript `ScopesIDLists.ts` in the SDK distribution.

public enum ScopeKind: String, Sendable, Codable {
    /// Opens a host view through `ui.openView`.
    case view
    /// Calls an IPC method.
    case api
}

public struct ScopeEntry: Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let kind: ScopeKind
    public let ipcMethod: String?
    public let capabilityId: SDKCapabilityID
    public let viewId: String?

    public init(id: String, title: String, description: String, kind: ScopeKind, ipcMethod: String? = nil, capabilityId: SDKCapabilityID, viewId: String? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.ipcMethod = ipcMethod
        self.capabilityId = capabilityId
        self.viewId = viewId
    }
}

public enum ScopesIDLists {
    /// All scopes, in registry order.
    public static let all: [ScopeEntry] = [
        ScopeEntry(id: "project.read", title: "Project metadata", description: "Read basic facts about the active project.", kind: .api, ipcMethod: nil, capabilityId: .projectRead),
        ScopeEntry(id: "workspace.read", title: "Workspace file reading", description: "Read files inside the approved workspace scope.", kind: .api, capabilityId: .workspaceRead),
        ScopeEntry(id: "workspace.write", title: "Workspace file writing", description: "Create or modify files inside the approved workspace through the host's constrained file API.", kind: .api, capabilityId: .workspaceWrite),
        ScopeEntry(id: "source-control.read", title: "Source control reading", description: "Inspect repository status, diffs, branch, and approved history. Read-only.", kind: .api, ipcMethod: "sourceControl.getStatus", capabilityId: .sourceControlRead),
        ScopeEntry(id: "source-control.write", title: "Source control changes", description: "Perform explicitly supported source-control mutations.", kind: .api, capabilityId: .sourceControlWrite),
        ScopeEntry(id: "build.execute", title: "Build execution", description: "Request builds through SwiftCode's managed build service.", kind: .api, ipcMethod: "build.run", capabilityId: .buildExecute),
        ScopeEntry(id: "task.execute", title: "Host task execution", description: "Invoke approved host task types.", kind: .api, capabilityId: .taskExecute),
        ScopeEntry(id: "network.request", title: "Network requests", description: "Make network requests constrained by host policy.", kind: .api, capabilityId: .networkRequest),
        ScopeEntry(id: "ui.contribute", title: "UI contributions", description: "Register supported extension UI contributions.", kind: .api, ipcMethod: "commands.register", capabilityId: .uiContribute),
        ScopeEntry(id: "credentials.use", title: "Credential use", description: "Use a narrowly scoped, host-mediated credential for an approved service.", kind: .api, capabilityId: .credentialsUse),
        ScopeEntry(id: "assist.invoke", title: "Assist invocation", description: "Request Assist operations. Unavailable to extensions in this release.", kind: .api, ipcMethod: "assist.invoke", capabilityId: .assistInvoke),
        ScopeEntry(id: "assist.ui", title: "Assist embedded UI", description: "Embed the host's Assist main view. Entitlement-only.", kind: .api, ipcMethod: "assist.invoke", capabilityId: .assistUI),
        ScopeEntry(id: "assist.headless", title: "Assist headless API", description: "Drive Assist sessions over the entitled assist.invoke route. Entitlement-only.", kind: .api, ipcMethod: "assist.invoke", capabilityId: .assistHeadless),
        ScopeEntry(id: "use.SwiftCodeModel", title: "SwiftCode Cloud Model", description: "Call the SwiftCode Cloud Model through the host under host-enforced quota.", kind: .api, ipcMethod: "cloudModel.complete", capabilityId: .useSwiftCodeModel),
        ScopeEntry(id: "terminal.sandbox", title: "Sandboxed command execution", description: "Run allow-listed commands through the host's sandboxed execution service.", kind: .api, ipcMethod: "terminalSandbox.run", capabilityId: .terminalSandbox),
        ScopeEntry(id: "security.addValue", title: "Store a secret", description: "Store a named secret in the host's Keychain vault.", kind: .api, ipcMethod: "security.addValue", capabilityId: .securityAddValue),
        ScopeEntry(id: "security.hasValue", title: "Check a stored secret", description: "Check whether a named secret exists, without revealing the value.", kind: .api, ipcMethod: "security.hasValue", capabilityId: .securityHasValue),
        ScopeEntry(id: "security.listValueIDs", title: "List stored secret names", description: "List the names of the extension's stored secrets.", kind: .api, ipcMethod: "security.listValueIDs", capabilityId: .securityListValueIDs),
        ScopeEntry(id: "security.deleteValue", title: "Delete a stored secret", description: "Permanently delete a named stored secret.", kind: .api, ipcMethod: "security.deleteValue", capabilityId: .securityDeleteValue),
        ScopeEntry(id: "security.useValue", title: "Use a stored secret", description: "Have the host inject a stored secret into an approved operation.", kind: .api, ipcMethod: "security.useValue", capabilityId: .securityUseValue),
        ScopeEntry(id: "db.ExploreView", title: "Database Explorer", description: "Open the Database Explorer window for project databases.", kind: .view, ipcMethod: "ui.openView", capabilityId: .dbExploreView, viewId: "db.ExploreView"),
        ScopeEntry(id: "ci.VisualWF", title: "CI / visual workflow", description: "Open the CI and visual workflow views.", kind: .view, ipcMethod: "ui.openView", capabilityId: .ciVisualWF, viewId: "ci.VisualWF"),
        ScopeEntry(id: "sandbox.view", title: "Terminal", description: "Open SwiftCode's real Terminal view (full interactive shell).", kind: .view, ipcMethod: "ui.openView", capabilityId: .sandboxView, viewId: "sandbox.view"),
        ScopeEntry(id: "virtualization.view", title: "Virtualization console", description: "Open the Virtualization console.", kind: .view, ipcMethod: "ui.openView", capabilityId: .virtualizationView, viewId: "virtualization.view"),
        ScopeEntry(id: "deployConsole.view", title: "Deployments console", description: "Open the Deployments console.", kind: .view, ipcMethod: "ui.openView", capabilityId: .deployConsoleView, viewId: "deployConsole.view"),
        ScopeEntry(id: "simulator.view", title: "Simulator workspace", description: "Open the Simulator workspace.", kind: .view, ipcMethod: "ui.openView", capabilityId: .simulatorView, viewId: "simulator.view"),
        ScopeEntry(id: "preview.live", title: "Live SwiftUI preview", description: "Render live SwiftUI previews of project views.", kind: .view, ipcMethod: "ui.openView", capabilityId: .previewLive, viewId: "preview.live"),
        ScopeEntry(id: "uibuilder.open", title: "Visual UI Builder", description: "Open the Visual UI Builder.", kind: .view, ipcMethod: "ui.openView", capabilityId: .uiBuilderOpen, viewId: "uibuilder.open"),
        ScopeEntry(id: "symbols.browse", title: "SF Symbol picker", description: "Open the SF Symbol picker.", kind: .view, ipcMethod: "ui.openView", capabilityId: .symbolsBrowse, viewId: "symbols.browse"),
        ScopeEntry(id: "docs.search", title: "Documentation browser", description: "Open the documentation browser.", kind: .view, ipcMethod: "ui.openView", capabilityId: .docsSearch, viewId: "docs.search"),
        ScopeEntry(id: "dictionary.open", title: "Coding dictionary", description: "Open the coding dictionary reference.", kind: .view, ipcMethod: "ui.openView", capabilityId: .dictionaryOpen, viewId: "dictionary.open"),
        ScopeEntry(id: "deviceconnect.open", title: "Device Connect", description: "Open the Device Connect surface for paired devices.", kind: .view, ipcMethod: "ui.openView", capabilityId: .deviceConnectOpen, viewId: "deviceconnect.open"),
    ]

    public static let byId: [String: ScopeEntry] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Opens a view scope, or throws for an API scope / unknown scope.
    /// View scopes open through the view-opener registry; API scopes are
    /// not "openable" — they are authorized per call by the broker.
    public static func openScope(id: String) async throws {
        guard let entry = byId[id] else {
            throw SDKError(code: .unknownCapability, message: "Unknown scope: \(id).")
        }
        switch entry.kind {
        case .view:
            guard let viewId = entry.viewId else {
                throw SDKError(code: .invalidArgument, message: "The scope has no view to open.")
            }
            try await SDKViewOpener.shared.open(viewID: viewId)
        case .api:
            throw SDKError(code: .invalidArgument, message: "The scope \(id) is an API capability, not a view.")
        }
    }
}
