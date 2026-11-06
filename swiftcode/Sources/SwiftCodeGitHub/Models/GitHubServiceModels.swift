import Foundation

/// A GitHub Discussion thread (`POST /graphql`, mapped by
/// `GitHubService.fetchDiscussions`). Ported verbatim from Legacy
/// `SwiftCode/Backend/Git/GitHubService.swift` (`DiscussionThread`), with
/// an explicit public memberwise init — Legacy's was internal, and
/// `DiscussionsView` (SwiftCodeUI) constructs replies itself.
public struct DiscussionThread: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let category: String
    public let body: String
    public var votes: Int
    public let replies: [DiscussionReply]
    public let date: String

    public init(
        id: String,
        title: String,
        author: String,
        category: String,
        body: String,
        votes: Int,
        replies: [DiscussionReply],
        date: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.category = category
        self.body = body
        self.votes = votes
        self.replies = replies
        self.date = date
    }
}

/// One comment on a discussion thread. Ported verbatim from Legacy
/// `SwiftCode/Backend/Git/GitHubService.swift` (`DiscussionReply`), with
/// an explicit public memberwise init (see `DiscussionThread`).
public struct DiscussionReply: Identifiable, Sendable {
    public let id: String
    public let author: String
    public let body: String
    public var isAccepted: Bool
    public let date: String

    public init(
        id: String,
        author: String,
        body: String,
        isAccepted: Bool,
        date: String
    ) {
        self.id = id
        self.author = author
        self.body = body
        self.isAccepted = isAccepted
        self.date = date
    }
}
