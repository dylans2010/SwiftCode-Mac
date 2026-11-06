import Foundation

/// Session-scoped working directories for Assist (`dir_cd` / `dir_pwd`).
///
/// The store is keyed by session ID and holds the directory a session's
/// `dir_cd` last established. It is in-memory only: a new session starts at
/// the workspace root, and a resumed session re-applies its stored directory
/// via `AssistContextBuilder` when the context is rebuilt. It is never
/// persisted to disk and never shared across sessions.
///
/// Filesystem tools resolve plain relative paths against the stored
/// directory (see `AssistFileSystem.currentDirectory`); paths with a leading
/// "/" still resolve against the workspace root. `use_terminal` defaults its
/// working directory to the stored directory when no `workingDirectory` is
/// given, so one `dir_cd` applies to both native tools and terminal calls.
@MainActor
public final class AssistWorkingDirectoryStore {
    public static let shared = AssistWorkingDirectoryStore()
    private var directories: [UUID: URL] = [:]

    private init() {}

    public func currentDirectory(for sessionId: UUID, workspaceRoot: URL) -> URL {
        directories[sessionId] ?? workspaceRoot
    }

    public func setCurrentDirectory(_ url: URL, for sessionId: UUID) {
        directories[sessionId] = url
    }

    public func clear(for sessionId: UUID) {
        directories.removeValue(forKey: sessionId)
    }
}
