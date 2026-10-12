import Foundation

// MARK: - SDKCapabilityID
//
// The fixed capability registry (spec Docs/Intro-to-SDK.md §8.1,
// ADR SwiftCode/SDK/Documentation/SDK-Architecture.md §7).
// This registry is FIXED for Phase 1+: do not rename or remove cases.
// Additive cases require a minor SDK version bump and a Compatibility.md entry.
//
// Raw values are the exact capability IDs used in manifests, grant records,
// and IPC messages. They are part of the wire contract: never change them.
//
// ID naming: the registry carries two historical conventions. The original
// Phase 1 IDs use kebab-case `domain.action` (e.g. `"source-control.read"`);
// the later platform-capability IDs use `<area>.<View>` camel/Pascal form
// (e.g. `"db.ExploreView"`). Both spellings are valid, case-sensitive wire
// IDs — match them verbatim and never normalize or re-case them.

public enum SDKCapabilityID: String, Sendable, Codable, CaseIterable {
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
    case assistInvoke = "assist.invoke"
    case dbExploreView = "db.ExploreView"
    case ciVisualWF = "ci.VisualWF"
    case sandboxView = "sandbox.view"
    case useSwiftCodeModel = "use.SwiftCodeModel"
    case terminalSandbox = "terminal.sandbox"
    case simulatorView = "simulator.view"
    case previewLive = "preview.live"
    case uiBuilderOpen = "uibuilder.open"
    case symbolsBrowse = "symbols.browse"
    case docsSearch = "docs.search"
    case dictionaryOpen = "dictionary.open"
    case deviceConnectOpen = "deviceconnect.open"
}

// MARK: - SDKCapabilityRisk

/// Risk tier for a capability. Drives approval-UX presentation and the
/// built-in Developer API Key scope requirements (spec §8.2.1).
public enum SDKCapabilityRisk: String, Sendable, Codable {
    /// Read-only, safe metadata. No mutation, no content access.
    case low = "low"

    /// Broader read access (file contents, UI surface). No mutation.
    case medium = "medium"

    /// Mutation, execution, network, or secret use. Always requires an
    /// explicit grant; privileged capabilities also require an authenticated
    /// Developer API Key with explicit scopes (spec §8.2.1).
    case high = "high"

    /// Not grantable in this release. Any request is denied with a typed
    /// `ASSIST_DENIED` error and recorded as an audit event (ADR §9).
    case restricted = "restricted"
}

// MARK: - SDKCapabilityInfo

/// Human-readable, user-facing description of one capability.
///
/// The `description`, `grantsSummary`, and `doesNotGrant` fields power the
/// approval UX (spec §8.3): explain the practical effects in plain language
/// and never bury what a capability does — or does not — allow.
public struct SDKCapabilityInfo: Sendable {
    /// The capability identifier (wire-stable raw value).
    public let id: SDKCapabilityID

    /// Short user-facing title, e.g. "Source control reading".
    public let title: String

    /// Plain-language practical effects, 1–3 sentences.
    public let description: String

    /// What this capability allows.
    public let grantsSummary: String

    /// What this capability explicitly does NOT allow.
    public let doesNotGrant: String

    /// Risk tier driving approval UX and API-key scope requirements.
    public let risk: SDKCapabilityRisk

    /// Whether the host may grant this capability in the current release.
    /// `false` only for `assist.invoke` (ADR §9).
    public let grantableInCurrentRelease: Bool

    public init(
        id: SDKCapabilityID,
        title: String,
        description: String,
        grantsSummary: String,
        doesNotGrant: String,
        risk: SDKCapabilityRisk,
        grantableInCurrentRelease: Bool
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.grantsSummary = grantsSummary
        self.doesNotGrant = doesNotGrant
        self.risk = risk
        self.grantableInCurrentRelease = grantableInCurrentRelease
    }
}

// MARK: - SDKCapabilityRegistry

/// Authoritative lookup for the fixed capability registry.
///
/// `info(for:)` uses an exhaustive switch, so adding a new `SDKCapabilityID`
/// case without adding its info fails to compile — the registry cannot
/// silently drift out of sync with the ID set.
public enum SDKCapabilityRegistry {
    /// All registered capabilities, in spec §8.1 table order.
    public static let all: [SDKCapabilityInfo] = SDKCapabilityID.allCases.map(info(for:))

    /// User-facing info for a capability ID. Total: every case is covered.
    public static func info(for id: SDKCapabilityID) -> SDKCapabilityInfo {
        switch id {
        case .projectRead:
            return SDKCapabilityInfo(
                id: id,
                title: "Project metadata",
                description: "Lets the extension read basic facts about the currently active project, like its name and identity. The host defines what counts as safe metadata.",
                grantsSummary: "Read safe metadata about the active project.",
                doesNotGrant: "File contents or project mutation.",
                risk: .low,
                grantableInCurrentRelease: true
            )
        case .workspaceRead:
            return SDKCapabilityInfo(
                id: id,
                title: "Workspace file reading",
                description: "Lets the extension read files inside the approved workspace scope. Files outside that scope stay out of reach.",
                grantsSummary: "Read files within the approved workspace scope.",
                doesNotGrant: "Access outside the workspace.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        case .workspaceWrite:
            return SDKCapabilityInfo(
                id: id,
                title: "Workspace file writing",
                description: "Lets the extension create or modify files inside the approved workspace through the host's constrained file API. Every write is mediated by the host.",
                grantsSummary: "Write approved workspace files through a constrained API.",
                doesNotGrant: "Arbitrary filesystem access.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .sourceControlRead:
            return SDKCapabilityInfo(
                id: id,
                title: "Source control reading",
                description: "Lets the extension inspect the repository: working-tree status, diffs, the current branch, and approved commit history. Strictly read-only.",
                grantsSummary: "Read repository status, diffs, branch and approved history metadata.",
                doesNotGrant: "Stage, commit, checkout, reset, push or other mutations.",
                risk: .low,
                grantableInCurrentRelease: true
            )
        case .sourceControlWrite:
            return SDKCapabilityInfo(
                id: id,
                title: "Source control changes",
                description: "Lets the extension perform source-control mutations that the host explicitly supports. The extension cannot run arbitrary Git commands.",
                grantsSummary: "Perform explicitly supported source-control mutations.",
                doesNotGrant: "Arbitrary Git commands.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .buildExecute:
            return SDKCapabilityInfo(
                id: id,
                title: "Build execution",
                description: "Lets the extension request builds through SwiftCode's managed build service. Approving this capability may run a potentially expensive build, and the host manages its execution.",
                grantsSummary: "Request builds through SwiftCode's managed build service.",
                doesNotGrant: "Arbitrary shell/process execution or unrestricted build-setting injection.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .taskExecute:
            return SDKCapabilityInfo(
                id: id,
                title: "Host task execution",
                description: "Lets the extension invoke approved host task types through the host's task service. Only task types the host defines can be invoked.",
                grantsSummary: "Invoke approved host task types.",
                doesNotGrant: "General process execution.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .networkRequest:
            return SDKCapabilityInfo(
                id: id,
                title: "Network requests",
                description: "Lets the extension make network requests constrained by host policy, such as allowed destinations and limits. The host enforces the policy on every request.",
                grantsSummary: "Make constrained network requests under host policy.",
                doesNotGrant: "Arbitrary sockets, unrestricted local-network access, or credential theft.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .uiContribute:
            return SDKCapabilityInfo(
                id: id,
                title: "UI contributions",
                description: "Lets the extension register supported UI contributions, such as commands that appear in the host's interface. Contributions are declared and rendered by the host.",
                grantsSummary: "Register supported extension UI contributions.",
                doesNotGrant: "Arbitrary native code injection.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        case .credentialsUse:
            return SDKCapabilityInfo(
                id: id,
                title: "Credential use",
                description: "Lets the extension use a narrowly scoped credential for an approved service, fully mediated by the host. The extension never sees the raw secret.",
                grantsSummary: "Use a narrowly scoped, host-mediated credential for an approved service.",
                doesNotGrant: "Read/export raw stored secrets.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .assistInvoke:
            return SDKCapabilityInfo(
                id: id,
                title: "Assist invocation",
                description: "Would let the extension request Assist operations under a separate authorization flow. Assist is unavailable to extensions in this release: any request is denied with a typed error and recorded as an audit event.",
                grantsSummary: "Request separately authorized Assist operations.",
                doesNotGrant: "Automatic access to Assist, user conversations, or all models/tools.",
                risk: .restricted,
                grantableInCurrentRelease: false
            )
        case .dbExploreView:
            return SDKCapabilityInfo(
                id: id,
                title: "Database Explorer",
                description: "Lets the extension open the real Database Explorer window for browsing project databases. All querying happens through the explorer's own UI and host-mediated connections.",
                grantsSummary: "Open the Database Explorer window for project databases.",
                doesNotGrant: "Arbitrary SQL execution outside the explorer or direct database-connection access.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        case .ciVisualWF:
            return SDKCapabilityInfo(
                id: id,
                title: "CI / visual workflow",
                description: "Lets the extension open the CI and visual workflow views to inspect pipelines and workflow graphs. The extension only gets a window into this surface, not control of it.",
                grantsSummary: "Open the CI / visual workflow views.",
                doesNotGrant: "Triggering pipeline runs or editing workflow definitions.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        case .sandboxView:
            return SDKCapabilityInfo(
                id: id,
                title: "Virtualization console",
                description: "Lets the extension open the Virtualization console to view virtual machine state. Virtualization can provision and mutate guest environments, so this is a high-risk surface.",
                grantsSummary: "Open the Virtualization console and view VM state.",
                doesNotGrant: "VM lifecycle actions outside the console's own controls.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .useSwiftCodeModel:
            return SDKCapabilityInfo(
                id: id,
                title: "SwiftCode Cloud Model",
                description: "Lets the extension call the SwiftCode Cloud Model through the host, which enforces the user's quota on every call. The extension never touches model credentials or the raw endpoint.",
                grantsSummary: "Invoke the SwiftCode Cloud Model through the host under host-enforced quota.",
                doesNotGrant: "Direct model-endpoint access, quota bypass, or use of other cloud models.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .terminalSandbox:
            return SDKCapabilityInfo(
                id: id,
                title: "Sandboxed command execution",
                description: "Lets the extension run shell commands through the host's sandboxed execution service. This is NOT a view: commands run without any terminal UI, always inside the sandbox the host defines.",
                grantsSummary: "Run sandboxed shell commands through host-mediated execution.",
                doesNotGrant: "Opening a terminal surface, unsandboxed shell access, or files outside the sandbox.",
                risk: .high,
                grantableInCurrentRelease: true
            )
        case .simulatorView:
            return SDKCapabilityInfo(
                id: id,
                title: "Simulator workspace",
                description: "Lets the extension open the Simulator workspace to view and interact with booted simulators. All simulator management stays inside the workspace's own UI.",
                grantsSummary: "Open the Simulator workspace.",
                doesNotGrant: "Creating, deleting, or retyping simulators outside the workspace.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        case .previewLive:
            return SDKCapabilityInfo(
                id: id,
                title: "Live SwiftUI preview",
                description: "Lets the extension render live SwiftUI previews of project views. Previews compile through the host's managed preview pipeline.",
                grantsSummary: "Render live SwiftUI previews.",
                doesNotGrant: "Editing source files through previews or unrestricted build execution beyond preview compilation.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        case .uiBuilderOpen:
            return SDKCapabilityInfo(
                id: id,
                title: "Visual UI Builder",
                description: "Lets the extension open the Visual UI Builder for composing interfaces. Applying changes to the project happens through the builder's own flow, not through the extension.",
                grantsSummary: "Open the Visual UI Builder.",
                doesNotGrant: "Applying UI changes to the project outside the builder's own flow.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        case .symbolsBrowse:
            return SDKCapabilityInfo(
                id: id,
                title: "SF Symbol picker",
                description: "Lets the extension open the SF Symbol picker so the user can browse and pick system symbols. Purely informational.",
                grantsSummary: "Browse and pick SF Symbols.",
                doesNotGrant: "Any system modification, network access, or file access.",
                risk: .low,
                grantableInCurrentRelease: true
            )
        case .docsSearch:
            return SDKCapabilityInfo(
                id: id,
                title: "Documentation browser",
                description: "Lets the extension open the documentation browser to search and read developer documentation. Read-only reference access.",
                grantsSummary: "Search and read documentation.",
                doesNotGrant: "Network access beyond the doc browser or any file mutation.",
                risk: .low,
                grantableInCurrentRelease: true
            )
        case .dictionaryOpen:
            return SDKCapabilityInfo(
                id: id,
                title: "Coding dictionary",
                description: "Lets the extension open the coding dictionary for quick reference on APIs and language terms. Read-only reference access.",
                grantsSummary: "Open the coding dictionary reference.",
                doesNotGrant: "Network access beyond the dictionary or any project modification.",
                risk: .low,
                grantableInCurrentRelease: true
            )
        case .deviceConnectOpen:
            return SDKCapabilityInfo(
                id: id,
                title: "Device Connect",
                description: "Lets the extension open the Device Connect surface for managing paired Apple devices. Device operations stay inside Device Connect's own controls.",
                grantsSummary: "Open the Device Connect surface for paired devices.",
                doesNotGrant: "Device pairing authorization or destructive device operations outside the console's own controls.",
                risk: .medium,
                grantableInCurrentRelease: true
            )
        }
    }

    /// User-facing info for a raw capability ID string, e.g. from a manifest.
    /// Returns `nil` when the ID is not a known capability; the host's strict
    /// validator maps that to `SDKErrorCode.unknownCapability` (P1b).
    public static func info(forRawValue rawValue: String) -> SDKCapabilityInfo? {
        guard let id = SDKCapabilityID(rawValue: rawValue) else { return nil }
        return info(for: id)
    }
}
