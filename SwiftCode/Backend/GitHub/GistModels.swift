import Foundation

public struct GistFile: Codable, Identifiable, Equatable {
    public let id: UUID
    public var filename: String
    public var content: String
    public var language: String?
    public var rawUrl: String?
    public var size: Int?

    public init(id: UUID = UUID(), filename: String, content: String, language: String? = nil, rawUrl: String? = nil, size: Int? = nil) {
        self.id = id
        self.filename = filename
        self.content = content
        self.language = language
        self.rawUrl = rawUrl
        self.size = size
    }

    public var patch: String?

    public init(id: UUID = UUID(), filename: String, content: String, language: String? = nil, rawUrl: String? = nil, size: Int? = nil, patch: String? = nil) {
        self.id = id
        self.filename = filename
        self.content = content
        self.language = language
        self.rawUrl = rawUrl
        self.size = size
        self.patch = patch
    }

    public enum CodingKeys: String, CodingKey {
        case filename, content, language, size, patch
        case rawUrl = "raw_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.filename = try container.decode(String.self, forKey: .filename)
        self.content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.language = try container.decodeIfPresent(String.self, forKey: .language)
        self.rawUrl = try container.decodeIfPresent(String.self, forKey: .rawUrl)
        self.size = try container.decodeIfPresent(Int.self, forKey: .size)
        self.patch = try container.decodeIfPresent(String.self, forKey: .patch)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filename, forKey: .filename)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(rawUrl, forKey: .rawUrl)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encodeIfPresent(patch, forKey: .patch)
    }
}

public struct GistOwner: Codable {
    public let login: String
    public let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

public struct GistResponse: Codable, Identifiable {
    public let id: String
    public let htmlUrl: String
    public let gitPullUrl: String?
    public let gitPushUrl: String?
    public let description: String?
    public let `public`: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let owner: GistOwner?
    public let files: [String: GistFile]
    public let history: [GistHistoryEntry]?

    enum CodingKeys: String, CodingKey {
        case id
        case htmlUrl = "html_url"
        case gitPullUrl = "git_pull_url"
        case gitPushUrl = "git_push_url"
        case description
        case `public`
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case owner
        case files
        case history
    }
}

public struct GistHistoryEntry: Codable, Identifiable {
    public var id: String { version }
    public let version: String
    public let committedAt: Date?

    enum CodingKeys: String, CodingKey {
        case version
        case committedAt = "committed_at"
    }
}

public struct GistComment: Codable, Identifiable {
    public let id: Int
    public let body: String
    public let user: GistOwner?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, user
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct GistRevision: Codable, Identifiable {
    public var id: String { version }
    public let version: String
    public let user: GistOwner?
    public let changeStatus: ChangeStatus?
    public let committedAt: Date

    public struct ChangeStatus: Codable {
        public let total: Int?
        public let additions: Int?
        public let deletions: Int?
    }

    enum CodingKeys: String, CodingKey {
        case version, user
        case changeStatus = "change_status"
        case committedAt = "committed_at"
    }
}

public struct CreateGistRequest: Encodable {
    public let description: String?
    public let `public`: Bool
    public let files: [String: FileContent]

    public struct FileContent: Encodable {
        public let content: String
    }

    public init(description: String?, isPublic: Bool, files: [String: String]) {
        self.description = description
        self.public = isPublic
        self.files = files.mapValues { FileContent(content: $0) }
    }
}

public struct GistUpdateRequest: Encodable {
    public let description: String?
    public let files: [String: FileUpdateContent?]

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)

        var filesContainer = container.nestedContainer(keyedBy: DynamicKey.self, forKey: .files)
        for (filename, content) in files {
            if let content = content {
                try filesContainer.encode(content, forKey: DynamicKey(stringValue: filename)!)
            } else {
                try filesContainer.encodeNil(forKey: DynamicKey(stringValue: filename)!)
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case description, files
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public struct FileUpdateContent: Encodable {
        public let content: String?
        public let filename: String?

        public init(content: String? = nil, filename: String? = nil) {
            self.content = content
            self.filename = filename
        }
    }

    public init(description: String?, files: [String: FileUpdateContent?]) {
        self.description = description
        self.files = files
    }
}

public enum GistError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case apiError(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from GitHub."
        case .apiError(let message):
            return "GitHub API error: \(message)"
        case .notFound:
            return "Gist not found."
        }
    }
}
