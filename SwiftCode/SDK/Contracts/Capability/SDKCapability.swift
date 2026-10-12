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
