import Foundation

public struct Attachment: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable { case file, selection }
    public var kind: Kind
    public var path: String
    public var startLine: Int?
    public var endLine: Int?
    public var text: String

    public init(kind: Kind, path: String, startLine: Int? = nil, endLine: Int? = nil, text: String) {
        self.kind = kind
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
        self.text = text
    }

    public var label: String {
        let name = (path as NSString).lastPathComponent
        guard kind == .selection, let s = startLine, let e = endLine else { return name }
        return s == e ? "\(name):\(s)" : "\(name):\(s)–\(e)"
    }
}

public struct ProposalTarget: Codable, Sendable, Equatable {
    public var path: String
    public var selectionLocation: Int?
    public var selectionLength: Int?
    public var selectionText: String?
    public init(path: String, selectionLocation: Int? = nil, selectionLength: Int? = nil, selectionText: String? = nil) {
        self.path = path
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
        self.selectionText = selectionText
    }
}

public struct ConversationMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var attachments: [Attachment]
    public var date: Date
    public var source: String?
    public var error: String?
    public var isComplete: Bool
    public var activity: [String]
    public var target: ProposalTarget?
    public var resolvedProposals: [Int: ProposalResolution]
    public var isCutOff: Bool?

    public init(id: UUID = UUID(), role: ChatRole, text: String, attachments: [Attachment] = [], date: Date = Date(), source: String? = nil,
                error: String? = nil, isComplete: Bool = true, activity: [String] = [], target: ProposalTarget? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.attachments = attachments
        self.date = date
        self.source = source
        self.error = error
        self.isComplete = isComplete
        self.activity = activity
        self.target = target
        self.resolvedProposals = [:]
    }
}

public enum ProposalResolution: String, Codable, Sendable { case accepted, rejected }

public struct Conversation: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var created: Date
    public var messages: [ConversationMessage]
    public var provider: ProviderKind?
    public var model: String?
    public var groupID: UUID?
    public var isArchived: Bool

    public static let untitled = "New Conversation"

    public init(id: UUID = UUID(), title: String = Self.untitled, created: Date = Date(), messages: [ConversationMessage] = [],
                provider: ProviderKind? = nil, model: String? = nil, groupID: UUID? = nil, isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.created = created
        self.messages = messages
        self.provider = provider
        self.model = model
        self.groupID = groupID
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey { case id, title, created, messages, provider, model, groupID, isArchived }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        created = try c.decode(Date.self, forKey: .created)
        messages = try c.decode([ConversationMessage].self, forKey: .messages)
        provider = try c.decodeIfPresent(ProviderKind.self, forKey: .provider)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    public var isActive: Bool { messages.last.map { $0.role == .assistant && !$0.isComplete } ?? false }

    public static func title(fromPrompt p: String) -> String {
        let line = p.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return untitled }
        return line.count > 48 ? String(line.prefix(47)) + "…" : line
    }

    public var history: [ChatMessage] {
        messages.filter { $0.isComplete && $0.error == nil && !$0.text.isEmpty }.map { ChatMessage($0.role, $0.text) }
    }
}

public struct ConversationGroup: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var created: Date

    public static let untitled = "New Group"

    public init(id: UUID = UUID(), title: String = Self.untitled, created: Date = Date()) {
        self.id = id
        self.title = title
        self.created = created
    }
}

public struct ConversationLibrary: Codable, Sendable, Equatable {
    public var conversations: [Conversation]
    public var groups: [ConversationGroup]

    public init(conversations: [Conversation] = [], groups: [ConversationGroup] = []) {
        self.conversations = conversations
        self.groups = groups
    }

    public enum Node: Equatable, Sendable {
        case group(ConversationGroup, [Conversation])
        case conversation(Conversation)
        case archive([Conversation])
    }

    public static let archiveTitle = "Archive"

    public var outline: [Node] {
        let newestFirst = conversations.reversed()
        let known = Set(groups.map(\.id))
        var nodes: [Node] = groups.map { g in .group(g, newestFirst.filter { !$0.isArchived && $0.groupID == g.id }) }
        nodes += newestFirst.filter { !$0.isArchived && ($0.groupID.map { !known.contains($0) } ?? true) }.map(Node.conversation)
        nodes.append(.archive(newestFirst.filter(\.isArchived)))
        return nodes
    }

    public func unusedGroupTitle(_ base: String = ConversationGroup.untitled) -> String {
        let used = Set(groups.map(\.title))
        guard used.contains(base) else { return base }
        var n = 2
        while used.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}

public enum ConversationArchive {
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func loadLibrary(_ url: URL) -> ConversationLibrary {
        guard let d = try? Data(contentsOf: url) else { return ConversationLibrary() }
        if let library = try? decoder.decode(ConversationLibrary.self, from: d) { return library }
        return ConversationLibrary(conversations: (try? decoder.decode([Conversation].self, from: d)) ?? [])
    }

    public static func load(_ url: URL) -> [Conversation] { loadLibrary(url).conversations }

    public static func save(_ conversations: [Conversation], to url: URL) throws {
        try save(ConversationLibrary(conversations: conversations), to: url)
    }

    public static func save(_ library: ConversationLibrary, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var settled = library
        settled.conversations = library.conversations.map { c -> Conversation in
            var c = c
            for i in c.messages.indices where !c.messages[i].isComplete {
                c.messages[i].isComplete = true
                if c.messages[i].error == nil { c.messages[i].error = "Interrupted." }
            }
            return c
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(settled).write(to: url, options: .atomic)
    }
}
