// The project an Assist session operates on, as seen from SwiftCodeAssistant.
// V2 fix (A6 slice): AssistContext / AssistGitManager / AssistManager /
// AssistContextBuilder referenced `Project` and `ProjectSessionStore.shared`,
// which live in SwiftCodeIDECore — a target SwiftCodeAssistant cannot depend
// on (SwiftCodeIDECore already depends on SwiftCodeAssistant; the reverse
// would be a dependency cycle). The assistant only ever reads two facts
// about a project — its display name and its directory — so those live here
// as a plain value. The IDE shell owns the real project: it sets
// `activeProject` on AssistManager.shared / AssistContextBuilder (or passes
// one to the builder) when a project opens. Until then the workspace root on
// disk is the project (name = its last path component), which is exactly
// what the old call sites derived from the store. No behaviour is dropped:
// name/directoryURL are the only members the old code read.

import Foundation

/// The active project, from the assistant's point of view: a name and a
/// directory. Converted from SwiftCodeIDECore's `Project` by the IDE shell
/// at the wiring boundary (`AssistProject(directoryURL:)` covers the
/// workspace-root case, where the root itself is the project).
public struct AssistProject: Sendable, Codable, Hashable {
    public let name: String
    public let directoryURL: URL

    public init(name: String, directoryURL: URL) {
        self.name = name
        self.directoryURL = directoryURL
    }

    /// The project implied by a workspace root on disk: the root itself.
    public init(workspaceRoot: URL) {
        self.init(name: workspaceRoot.lastPathComponent, directoryURL: workspaceRoot)
    }
}
