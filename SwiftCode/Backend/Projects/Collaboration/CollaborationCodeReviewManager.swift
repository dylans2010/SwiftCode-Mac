import Foundation

public struct ReviewEvent: Equatable {
    public let actorID: String
    public let title: String
    public let detail: String
    public let notifies: Bool
}

public enum ReviewStatus: String, Codable, CaseIterable {
    case pending
    case approved
    case rejected
    case changesRequested
}

public struct ReviewComment: Identifiable, Codable, Equatable {
    public let id: UUID
    public let authorID: String
    public let filePath: String
    public let lineNumber: Int
    public let text: String
    public let timestamp: Date
    public let parentID: UUID?

    public init(authorID: String, filePath: String, lineNumber: Int, text: String, parentID: UUID? = nil) {
        self.id = UUID()
        self.authorID = authorID
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.text = text
        self.timestamp = Date()
        self.parentID = parentID
    }
}

public struct ReviewHistoryEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let actorID: String
    public let filePath: String?
    public let message: String
    public let timestamp: Date

    public init(actorID: String, filePath: String? = nil, message: String) {
        self.id = UUID()
        self.actorID = actorID
        self.filePath = filePath
        self.message = message
        self.timestamp = Date()
    }
}

public struct CodeReview: Identifiable, Codable, Equatable {
    public let id: UUID
    public let commitID: UUID
    public var status: ReviewStatus
    public var comments: [ReviewComment]
    public var reviewerIDs: [String]
    public var history: [ReviewHistoryEntry]

    public init(commitID: UUID) {
        self.id = UUID()
        self.commitID = commitID
        self.status = .pending
        self.comments = []
        self.reviewerIDs = []
        self.history = []
    }
}

@MainActor
public final class CollaborationCodeReviewManager: ObservableObject {
    @Published public private(set) var reviews: [UUID: CodeReview] = [:]
    @Published public private(set) var lastEvent: ReviewEvent?

    public func initiateReview(for commitID: UUID) {
        if reviews[commitID] == nil {
            reviews[commitID] = CodeReview(commitID: commitID)
        }
    }

    public func assignReviewer(_ reviewerID: String, to commitID: UUID, actorID: String) {
        initiateReview(for: commitID)
        if reviews[commitID]?.reviewerIDs.contains(reviewerID) == false {
            reviews[commitID]?.reviewerIDs.append(reviewerID)
            reviews[commitID]?.history.insert(ReviewHistoryEntry(actorID: actorID, message: "Assigned reviewer \(reviewerID)"), at: 0)
            lastEvent = ReviewEvent(actorID: actorID, title: "Reviewer Assigned", detail: "\(reviewerID) added to review.", notifies: true)
        }
    }

    public func approveReview(for commitID: UUID, actorID: String) {
        updateStatus(for: commitID, status: .approved, actorID: actorID, message: "Approved Review")
    }

    public func rejectReview(for commitID: UUID, actorID: String) {
        updateStatus(for: commitID, status: .rejected, actorID: actorID, message: "Rejected Review")
    }

    public func requestChanges(for commitID: UUID, actorID: String) {
        updateStatus(for: commitID, status: .changesRequested, actorID: actorID, message: "Requested Changes")
    }

    public func addComment(to commitID: UUID, authorID: String, filePath: String, lineNumber: Int, text: String, parentID: UUID? = nil) {
        initiateReview(for: commitID)
        let comment = ReviewComment(authorID: authorID, filePath: filePath, lineNumber: lineNumber, text: text, parentID: parentID)
        reviews[commitID]?.comments.append(comment)
        reviews[commitID]?.history.insert(ReviewHistoryEntry(actorID: authorID, filePath: filePath, message: "Commented on \(filePath):\(lineNumber)"), at: 0)
        lastEvent = ReviewEvent(actorID: authorID, title: "Inline Comment Added", detail: "\(filePath):\(lineNumber)", notifies: false)
    }

    public func restoreState(reviews: [UUID: CodeReview]) {
        self.reviews = reviews
    }

    private func updateStatus(for commitID: UUID, status: ReviewStatus, actorID: String, message: String) {
        initiateReview(for: commitID)
        reviews[commitID]?.status = status
        reviews[commitID]?.history.insert(ReviewHistoryEntry(actorID: actorID, message: message), at: 0)
        lastEvent = ReviewEvent(actorID: actorID, title: message, detail: "Commit Rview Updated", notifies: true)
    }
}
