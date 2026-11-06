import Foundation

public struct GitFileStatus: Codable, Sendable, Equatable {
    public enum StatusType: String, Codable, Sendable {
        case modified = "modified"
        case added = "added"
        case deleted = "deleted"
        case untracked = "untracked"
        case renamed = "renamed"
        case copied = "copied"
        case ignored = "ignored"
    }

    public let path: String
    public let status: StatusType
    public let isStaged: Bool

    public init(path: String, status: StatusType, isStaged: Bool) {
        self.path = path
        self.status = status
        self.isStaged = isStaged
    }
}

public struct GitStatus: Codable, Sendable {
    public let isClean: Bool
    public let currentBranch: String
    public let upstreamBranch: String?
    public let aheadCount: Int
    public let behindCount: Int
    public let files: [GitFileStatus]

    public init(
        isClean: Bool,
        currentBranch: String,
        upstreamBranch: String? = nil,
        aheadCount: Int = 0,
        behindCount: Int = 0,
        files: [GitFileStatus] = []
    ) {
        self.isClean = isClean
        self.currentBranch = currentBranch
        self.upstreamBranch = upstreamBranch
        self.aheadCount = aheadCount
        self.behindCount = behindCount
        self.files = files
    }
}

public struct GitCommit: Codable, Sendable {
    public let hash: String
    public let shortHash: String
    public let authorName: String
    public let authorEmail: String
    public let date: Date
    public let message: String

    public init(
        hash: String,
        shortHash: String,
        authorName: String,
        authorEmail: String,
        date: Date,
        message: String
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.date = date
        self.message = message
    }
}

public struct GitBranch: Codable, Sendable {
    public let name: String
    public let isCurrent: Bool
    public let isRemote: Bool

    public init(name: String, isCurrent: Bool, isRemote: Bool) {
        self.name = name
        self.isCurrent = isCurrent
        self.isRemote = isRemote
    }
}

public struct GitRemote: Codable, Sendable {
    public let name: String
    public let fetchURL: String
    public let pushURL: String

    public init(name: String, fetchURL: String, pushURL: String) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }
}
