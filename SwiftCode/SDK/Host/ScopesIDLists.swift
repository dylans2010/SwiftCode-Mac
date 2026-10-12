import Foundation

// MARK: - ScopesIDLists
//
// The host-side canonical scope-ID table, mirroring
// SwiftCode/SDK/TypeScript/package/src/ScopesIDLists.ts (spec
// Docs/Intro-to-SDK.md §8.1 fixed capability registry, §10.4 IPC methods).
//
// Every entry carries the fixed `SDKCapabilityID` as a TYPED enum case —
// so a renamed or removed registry case fails to compile here — plus the
// primary IPC method serving the capability (`nil` when the host has not
// wired a method in this release; never a placeholder) and, for view
// entries, the `viewId` payload value for `ui.openView`.
//
// The 10 `view` entries delegate to `SDKViewOpener`'s REAL registered
// openers (`SDKViewOpenerBuiltIns.swift`) — nothing here is a stub. The
// 13 `api` entries are served by their host adapters over IPC
// (authorized per-call at `SDKCapabilityBroker` through the adapters, see
// `SDKIPCDispatcher`'s security model), NOT by this table: there is no
// view to open and this file must never fabricate one.
//
// ## SYNC CONTRACT
//
// This table and the TypeScript `SCOPES_ID_LIST` must stay identical:
// same IDs, same kinds, same ipcMethods, same viewIds. The test
// `SwiftCode/SDK/TypeScript/package/tests/scopes-sync.test.mjs` parses
// BOTH files and FAILS on any drift in either direction. When adding a
// capability to the fixed registry, add the entry in BOTH files in the
// same change (in registry order, matching `SDKCapabilityRegistry.all`).

public enum ScopesIDLists {

    public enum ScopeKind: String, Sendable {
        /// Opens a host view through `ui.openView`.
        case view
        /// Served by the host adapters over its own IPC method(s).
        case api
    }

    public struct ScopeEntry: Sendable {
        /// Lookup key and wire capability ID.
        public let id: String
        /// Short user-facing title (matches `SDKCapabilityInfo.title`).
        public let title: String
        /// One-sentence plain-language description of what the scope allows.
        public let description: String
        public let kind: ScopeKind
        /// Primary IPC method serving the capability, or `nil` when the
        /// host has not wired a method in this release — never a
        /// placeholder. A capability may span several methods
        /// (e.g. `build.execute` also covers `build.wait`/`build.cancel`);
        /// this field names the primary one.
        public let ipcMethod: String?
        /// The fixed registry case — typed so registry drift fails here.
        public let capabilityId: SDKCapabilityID
        /// For `kind == .view`: the exact `viewId` payload value sent to
        /// `ui.openView`. `nil` for API entries.
        public let viewId: String?

        public init(
            id: String,
            title: String,
            description: String,
            kind: ScopeKind,
            ipcMethod: String?,
            capabilityId: SDKCapabilityID,
            viewId: String?
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.kind = kind
            self.ipcMethod = ipcMethod
            self.capabilityId = capabilityId
            self.viewId = viewId
        }
    }

    /// Every capability in the fixed registry, in `SDKCapabilityRegistry.all`
    /// order. 10 are views; 13 are API capabilities. `ipcMethod == nil`
    /// means no host method is wired in this release — `assist.invoke`
    /// additionally being deny-by-default (spec §9, `SDKAssistGate`).
    public static let all: [ScopeEntry] = [
        ScopeEntry(
            id: "project.read",
            title: "Project metadata",
            description: "Read safe metadata about the active project, such as its name and identity.",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .projectRead,
            viewId: nil
        ),
        ScopeEntry(
            id: "workspace.read",
            title: "Workspace file reading",
            description: "Read files inside the approved workspace scope; files outside that scope stay out of reach.",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .workspaceRead,
            viewId: nil
        ),
        ScopeEntry(
            id: "workspace.write",
            title: "Workspace file writing",
            description: "Create or modify files inside the approved workspace through the host's constrained file API.",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .workspaceWrite,
            viewId: nil
        ),
        ScopeEntry(
            id: "source-control.read",
            title: "Source control reading",
            description: "Read repository status, diffs, branch, and approved history metadata.",
            kind: .api,
            ipcMethod: "sourceControl.getStatus",
            capabilityId: .sourceControlRead,
            viewId: nil
        ),
        ScopeEntry(
            id: "source-control.write",
            title: "Source control changes",
            description: "Perform explicitly supported source-control mutations; never arbitrary Git commands.",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .sourceControlWrite,
            viewId: nil
        ),
        ScopeEntry(
            id: "build.execute",
            title: "Build execution",
            description: "Request builds through SwiftCode's managed build service.",
            kind: .api,
            ipcMethod: "build.run",
            capabilityId: .buildExecute,
            viewId: nil
        ),
        ScopeEntry(
            id: "task.execute",
            title: "Host task execution",
            description: "Invoke approved host task types through the host's task service; never general process execution.",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .taskExecute,
            viewId: nil
        ),
        ScopeEntry(
            id: "network.request",
            title: "Network requests",
            description: "Make network requests constrained by host policy, such as allowed destinations and limits.",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .networkRequest,
            viewId: nil
        ),
        ScopeEntry(
            id: "ui.contribute",
            title: "UI contributions",
            description: "Register supported extension UI contributions, such as commands that appear in the host's interface.",
            kind: .api,
            ipcMethod: "commands.register",
            capabilityId: .uiContribute,
            viewId: nil
        ),
        ScopeEntry(
            id: "credentials.use",
            title: "Credential use",
            description: "Use a narrowly scoped, host-mediated credential for an approved service; the extension never sees the raw secret.",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .credentialsUse,
            viewId: nil
        ),
        ScopeEntry(
            id: "assist.invoke",
            title: "Assist invocation",
            description: "Assist is deny-by-default for extensions: never grantable, and no IPC method pattern reaches it (SDKAssistGate).",
            kind: .api,
            ipcMethod: nil,
            capabilityId: .assistInvoke,
            viewId: nil
        ),
        ScopeEntry(
            id: "db.ExploreView",
            title: "Database Explorer",
            description: "Open the Database Explorer window for browsing project databases.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .dbExploreView,
            viewId: "db.ExploreView"
        ),
        ScopeEntry(
            id: "ci.VisualWF",
            title: "CI / visual workflow",
            description: "Open the CI and visual workflow views to inspect pipelines and workflow graphs.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .ciVisualWF,
            viewId: "ci.VisualWF"
        ),
        ScopeEntry(
            id: "sandbox.view",
            title: "Virtualization console",
            description: "Open the Virtualization console to view virtual machine state.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .sandboxView,
            viewId: "sandbox.view"
        ),
        ScopeEntry(
            id: "use.SwiftCodeModel",
            title: "SwiftCode Cloud Model",
            description: "Invoke the SwiftCode Cloud Model through the host, under host-enforced quota.",
            kind: .api,
            ipcMethod: "cloudModel.complete",
            capabilityId: .useSwiftCodeModel,
            viewId: nil
        ),
        ScopeEntry(
            id: "terminal.sandbox",
            title: "Sandboxed command execution",
            description: "Run shell commands through the host's sandboxed execution service; this is not a terminal view.",
            kind: .api,
            ipcMethod: "terminalSandbox.run",
            capabilityId: .terminalSandbox,
            viewId: nil
        ),
        ScopeEntry(
            id: "simulator.view",
            title: "Simulator workspace",
            description: "Open the Simulator workspace to view and interact with booted simulators.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .simulatorView,
            viewId: "simulator.view"
        ),
        ScopeEntry(
            id: "preview.live",
            title: "Live SwiftUI preview",
            description: "Render live SwiftUI previews of project views through the host's managed preview pipeline.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .previewLive,
            viewId: "preview.live"
        ),
        ScopeEntry(
            id: "uibuilder.open",
            title: "Visual UI Builder",
            description: "Open the Visual UI Builder for composing interfaces.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .uiBuilderOpen,
            viewId: "uibuilder.open"
        ),
        ScopeEntry(
            id: "symbols.browse",
            title: "SF Symbol picker",
            description: "Open the SF Symbol picker to browse and pick system symbols.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .symbolsBrowse,
            viewId: "symbols.browse"
        ),
        ScopeEntry(
            id: "docs.search",
            title: "Documentation browser",
            description: "Open the documentation browser to search and read developer documentation.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .docsSearch,
            viewId: "docs.search"
        ),
        ScopeEntry(
            id: "dictionary.open",
            title: "Coding dictionary",
            description: "Open the coding dictionary for quick reference on APIs and language terms.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .dictionaryOpen,
            viewId: "dictionary.open"
        ),
        ScopeEntry(
            id: "deviceconnect.open",
            title: "Device Connect",
            description: "Open the Device Connect surface for managing paired Apple devices.",
            kind: .view,
            ipcMethod: "ui.openView",
            capabilityId: .deviceConnectOpen,
            viewId: "deviceconnect.open"
        ),
    ]

    /// `all` keyed by `id`. Every key is a wire capability ID.
    public static let byId: [String: ScopeEntry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// Opens the view-backed scope with `id` through its REAL registered
    /// opener (`SDKViewOpener` — authorization happens at
    /// `SDKCapabilityBroker` on the `ui.openView` IPC route before this
    /// is ever called; never call this from a path that bypasses that
    /// gate).
    ///
    /// API capabilities have no view and this file serves none of them —
    /// they are served by their host adapters over IPC (e.g. `build.run`,
    /// `terminalSandbox.run`), each authorizing at the broker on every
    /// call. Requesting an API scope here throws `.invalidArgument`
    /// instead of fabricating a view open.
    ///
    /// - Throws: `.unknownCapability` for an ID outside the fixed
    ///   registry; `.invalidArgument` for an API (non-view) capability;
    ///   `.serviceUnavailable` (or the opener's own typed error) from the
    ///   real opener when the view cannot be presented.
    public static func openScope(id: String) async throws {
        guard let entry = byId[id] else {
            throw SDKError(
                code: .unknownCapability,
                message: "Unknown scope \"\(id)\".",
                suggestion: "Use a capability ID from the SDK capability registry."
            )
        }
        switch entry.kind {
        case .view:
            try await SDKViewOpener.shared.open(viewID: entry.capabilityId)
        case .api:
            throw SDKError(
                code: .invalidArgument,
                message: "Capability \"\(entry.id)\" is an API capability: there is no view to open.",
                suggestion: entry.ipcMethod.map {
                    "API capabilities are served by their host adapters, not by view openers — call \"\($0)\" over IPC."
                } ?? "No host IPC method is wired for this capability in this release; it cannot be invoked.",
                diagnostics: ["capabilityId": entry.id]
            )
        }
    }
}
