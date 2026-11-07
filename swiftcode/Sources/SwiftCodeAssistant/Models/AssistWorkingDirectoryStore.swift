import Foundation

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
