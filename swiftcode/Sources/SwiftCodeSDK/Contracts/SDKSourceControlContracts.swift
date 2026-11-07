import Foundation

public enum SDKFileChangeStatus: String, Codable, Sendable {
    case modified
    case added
    case deleted
    case renamed
    case untracked
    case conflicted
}

public struct SDKFileChangeSummary: Codable, Sendable {
    public let path: String
    public let status: SDKFileChangeStatus
    public let isStaged: Bool

    public init(path: String, status: SDKFileChangeStatus, isStaged: Bool) {
        self.path = path
        self.status = status
        self.isStaged = isStaged
    }
}

public struct SDKRepositoryStatus: Codable, Sendable {
    public let isRepository: Bool
    public let branchName: String?
    public let ahead: Int
    public let behind: Int
    public let stagedCount: Int
    public let unstagedCount: Int
    public let untrackedCount: Int
    public let files: [SDKFileChangeSummary]

    public init(
        isRepository: Bool,
        branchName: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        stagedCount: Int = 0,
        unstagedCount: Int = 0,
        untrackedCount: Int = 0,
        files: [SDKFileChangeSummary] = []
    ) {
        self.isRepository = isRepository
        self.branchName = branchName
        self.ahead = ahead
        self.behind = behind
        self.stagedCount = stagedCount
        self.unstagedCount = unstagedCount
        self.untrackedCount = untrackedCount
        self.files = files
    }
}

public struct SDKDiffOptions: Codable, Sendable {
    public let maxBytes: Int
    public let includeUntracked: Bool
    public let paths: [String]?

    private enum CodingKeys: String, CodingKey {
        case maxBytes, includeUntracked, paths
    }

    public init(maxBytes: Int = 262_144, includeUntracked: Bool = true, paths: [String]? = nil) {
        self.maxBytes = max(1, maxBytes)
        self.includeUntracked = includeUntracked
        self.paths = paths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.maxBytes = max(1, try container.decodeIfPresent(Int.self, forKey: .maxBytes) ?? 262_144)
        self.includeUntracked = try container.decodeIfPresent(Bool.self, forKey: .includeUntracked) ?? true
        self.paths = try container.decodeIfPresent([String].self, forKey: .paths)
    }
}

public struct SDKFileDiff: Codable, Sendable {
    public let path: String
    public let hunks: [String]
    public let truncated: Bool

    public init(path: String, hunks: [String], truncated: Bool = false) {
        self.path = path
        self.hunks = hunks
        self.truncated = truncated
    }
}

public struct SDKRepositoryDiff: Codable, Sendable {
    public let files: [SDKFileDiff]
    public let truncated: Bool
    public let totalBytes: Int
    public let byteLimit: Int

    public init(files: [SDKFileDiff], truncated: Bool, totalBytes: Int, byteLimit: Int) {
        self.files = files
        self.truncated = truncated
        self.totalBytes = totalBytes
        self.byteLimit = byteLimit
    }
}
