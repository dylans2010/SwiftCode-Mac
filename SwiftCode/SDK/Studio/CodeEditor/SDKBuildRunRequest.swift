import Foundation

// MARK: - SDKBuildRunKind
//
// What the editor's build/run command should execute. The runner maps
// each kind to a concrete, real command line — no simulated builds:
//   - `.xcodebuildSwift`  → `xcodebuild` on the project at `projectRoot`
//                            (scheme from `schemeOrEntry`)
//   - `.typescriptExtension` → `npm run build` (or the manifest's build
//                            script) for an SDK TypeScript extension
//   - `.nodeScript`       → `node <schemeOrEntry>` for a single script

public enum SDKBuildRunKind: String, Sendable, Codable, CaseIterable, Hashable {
    case xcodebuildSwift
    case typescriptExtension
    case nodeScript

    /// User-facing display name, e.g. "xcodebuild (Swift)".
    public var displayName: String {
        switch self {
        case .xcodebuildSwift: return "xcodebuild (Swift)"
        case .typescriptExtension: return "TypeScript Extension"
        case .nodeScript: return "Node Script"
        }
    }
}

// MARK: - SDKBuildRunRequest
//
// A request to build or run a project from the Studio code editor.
// A VALUE TYPE: the requester constructs one and hands it to the build
// runner; the runner reports progress through `SDKConsoleEntry` lines on
// `SDKCodeEditorState`.
//
// Cancellation is cooperative and token-based: the requester keeps
// `taskID` and asks the runner to cancel that task. The `UUID` keeps this
// contract free of any specific concurrency primitive — the runner may
// back it with a `Task`, a `Process`, or anything else.

public struct SDKBuildRunRequest: Identifiable, Sendable, Hashable {
    /// Cancellation token for this run. Handed back to the runner's
    /// `cancel(taskID:)`; defaulting to a fresh UUID makes the common
    /// fire-and-forget case trivial.
    public let taskID: UUID

    /// Project root the build/run executes against.
    public let projectRoot: URL

    public let kind: SDKBuildRunKind

    /// Meaning depends on `kind`: the Xcode scheme for `.xcodebuildSwift`,
    /// the script path for `.nodeScript`, or `nil` when the kind needs no
    /// further disambiguation (`.typescriptExtension` uses the manifest).
    public let schemeOrEntry: String?

    public init(
        taskID: UUID = UUID(),
        projectRoot: URL,
        kind: SDKBuildRunKind,
        schemeOrEntry: String? = nil
    ) {
        self.taskID = taskID
        self.projectRoot = projectRoot
        self.kind = kind
        self.schemeOrEntry = schemeOrEntry
    }

    public var id: UUID { taskID }
}
