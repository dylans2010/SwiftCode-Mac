import Foundation

public struct GitWorktree: Identifiable, Codable, Sendable, Hashable {
    public var id: String { path } // Path is unique per worktree

    public let path: String
    public let headSHA: String
    public let branch: String? // nil if detached HEAD

    public var isMain: Bool = false
    public var isLocked: Bool = false
    public var lockReason: String? = nil

    // Detailed Metadata (loaded asynchronously)
    public var repositoryName: String = ""
    public var commitMessage: String = ""
    public var commitAuthor: String = ""
    public var commitDate: Date? = nil
    public var remoteBranch: String? = nil
    public var isDetached: Bool { branch == nil }

    // Status Information
    public var isDirty: Bool = false
    public var modifiedCount: Int = 0
    public var stagedCount: Int = 0
    public var untrackedCount: Int = 0
    public var aheadCount: Int = 0
    public var behindCount: Int = 0

    // Persistent User Preferences (stored in UserDefaults using path as key)
    public var isFavorite: Bool = false
    public var isPinned: Bool = false
    public var lastOpenedDate: Date? = nil

    public var relativePath: String {
        let repoName = (path as NSString).lastPathComponent
        return repoName
    }
}
