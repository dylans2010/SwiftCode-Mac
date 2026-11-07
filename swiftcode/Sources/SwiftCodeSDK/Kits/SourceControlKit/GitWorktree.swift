import Foundation

public struct GitWorktree: Identifiable, Codable, Sendable, Hashable {
    public var id: String { path }

    public let path: String
    public let headSHA: String
    public let branch: String?

    public var isMain: Bool = false
    public var isLocked: Bool = false
    public var lockReason: String? = nil

    public var repositoryName: String = ""
    public var commitMessage: String = ""
    public var commitAuthor: String = ""
    public var commitDate: Date? = nil
    public var remoteBranch: String? = nil
    public var isDetached: Bool { branch == nil }

    public var isDirty: Bool = false
    public var modifiedCount: Int = 0
    public var stagedCount: Int = 0
    public var untrackedCount: Int = 0
    public var aheadCount: Int = 0
    public var behindCount: Int = 0

    public var isFavorite: Bool = false
    public var isPinned: Bool = false
    public var lastOpenedDate: Date? = nil

    public var relativePath: String {
        let repoName = (path as NSString).lastPathComponent
        return repoName
    }
}
