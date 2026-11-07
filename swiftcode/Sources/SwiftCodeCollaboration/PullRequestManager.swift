import Foundation

public struct PullRequestEvent: Equatable {
    public let actorID: String
    public let title: String
    public let detail: String
    public let notifies: Bool
}

public enum PullRequestStatus: String, Codable, CaseIterable {
    case open
    case draft
    case approved
    case rejected
    case merged
    case closed
}

public enum PullRequestReviewDecision: String, Codable, CaseIterable {
    case comment
    case approve
    case requestChanges
    case reject

    public var title: String {
        switch self {
        case .comment: return "Comment"
        case .approve: return "Approve"
        case .requestChanges: return "Request Changes"
        case .reject: return "Reject"
        }
    }
}

public struct PullRequestComment: Identifiable, Codable, Equatable {
    public let id: UUID
    public let authorID: String
    public var text: String
    public let timestamp: Date
    public let filePath: String?
    public let lineNumber: Int?
    public let parentID: UUID?

    public init(authorID: String, text: String, filePath: String? = nil, lineNumber: Int? = nil, parentID: UUID? = nil) {
        self.id = UUID()
        self.authorID = authorID
        self.text = text
        self.timestamp = Date()
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.parentID = parentID
    }
}

public struct PullRequestReview: Identifiable, Codable, Equatable {
    public let id: UUID
    public let reviewerID: String
    public let decision: PullRequestReviewDecision
    public let summary: String
    public let timestamp: Date

    public init(reviewerID: String, decision: PullRequestReviewDecision, summary: String) {
        self.id = UUID()
        self.reviewerID = reviewerID
        self.decision = decision
        self.summary = summary
        self.timestamp = Date()
    }
}

public struct PullRequestTimelineEvent: Identifiable, Codable, Equatable {
    public let id: UUID
    public let actorID: String
    public let title: String
    public let detail: String
    public let timestamp: Date

    public init(actorID: String, title: String, detail: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.actorID = actorID
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
    }
}

public struct PullRequest: Identifiable, Codable, Equatable {
    public let id: UUID
    public let sourceBranchID: UUID
    public let targetBranchID: UUID
    public var title: String
    public var description: String
    public var status: PullRequestStatus
    public var authorID: String
    public let createdAt: Date
    public var comments: [PullRequestComment]
    public var mergeCommitID: UUID?
    public var reviewerIDs: [String]
    public var linkedCommitIDs: [UUID]
    public var reviews: [PullRequestReview]
    public var timeline: [PullRequestTimelineEvent]
    public var conflictSummary: String?

    public init(sourceBranchID: UUID, targetBranchID: UUID, title: String, description: String, authorID: String, status: PullRequestStatus = .open, linkedCommitIDs: [UUID] = [], conflictSummary: String? = nil) {
        self.id = UUID()
        self.sourceBranchID = sourceBranchID
        self.targetBranchID = targetBranchID
        self.title = title
        self.description = description
        self.status = status
        self.authorID = authorID
        self.createdAt = Date()
        self.comments = []
        self.reviewerIDs = []
        self.linkedCommitIDs = linkedCommitIDs
        self.reviews = []
        self.timeline = [
            PullRequestTimelineEvent(actorID: authorID, title: "Pull Request Created", detail: title)
        ]
        self.conflictSummary = conflictSummary
    }
}

@MainActor
public final class PullRequestManager: ObservableObject {
    @Published public private(set) var pullRequests: [PullRequest] = []
    @Published public private(set) var lastEvent: PullRequestEvent?

    public init() {}

    public func createPullRequest(
        sourceBranchID: UUID,
        targetBranchID: UUID,
        title: String,
        description: String,
        actorID: String,
        status: PullRequestStatus = .open,
        linkedCommitIDs: [UUID] = [],
        conflictSummary: String? = nil
    ) -> PullRequest {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Pull Request" : title
        let pr = PullRequest(
            sourceBranchID: sourceBranchID,
            targetBranchID: targetBranchID,
            title: normalizedTitle,
            description: description,
            authorID: actorID,
            status: status,
            linkedCommitIDs: linkedCommitIDs,
            conflictSummary: conflictSummary
        )
        pullRequests.insert(pr, at: 0)
        lastEvent = PullRequestEvent(actorID: actorID, title: "Pull Request Created", detail: normalizedTitle, notifies: true)
        return pr
    }

    public func editPullRequest(prID: UUID, title: String, description: String, actorID: String) {
        guard let index = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        pullRequests[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pullRequests[index].title : title
        pullRequests[index].description = description
        appendTimeline(to: index, actorID: actorID, title: "Details Edited", detail: pullRequests[index].title)
        lastEvent = PullRequestEvent(actorID: actorID, title: "Pull Request Updated", detail: pullRequests[index].title, notifies: false)
    }

    public func assignReviewer(_ reviewerID: String, to prID: UUID, actorID: String) {
        guard let index = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        guard pullRequests[index].reviewerIDs.contains(reviewerID) == false else { return }
        pullRequests[index].reviewerIDs.append(reviewerID)
        appendTimeline(to: index, actorID: actorID, title: "Reviewer Assigned", detail: reviewerID)
        lastEvent = PullRequestEvent(actorID: actorID, title: "Reviewer Assigned", detail: reviewerID, notifies: true)
    }

    public func linkCommit(_ commitID: UUID, to prID: UUID, actorID: String) {
        guard let index = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        guard pullRequests[index].linkedCommitIDs.contains(commitID) == false else { return }
        pullRequests[index].linkedCommitIDs.append(commitID)
        appendTimeline(to: index, actorID: actorID, title: "Commit Linked", detail: commitID.uuidString)
        lastEvent = PullRequestEvent(actorID: actorID, title: "Commit Linked", detail: pullRequests[index].title, notifies: false)
    }

    public func addComment(to prID: UUID, authorID: String, text: String, filePath: String? = nil, lineNumber: Int? = nil, parentID: UUID? = nil) {
        guard let index = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let comment = PullRequestComment(authorID: authorID, text: trimmed, filePath: filePath, lineNumber: lineNumber, parentID: parentID)
        pullRequests[index].comments.append(comment)
        let location = [filePath, lineNumber.map(String.init)].compactMap { $0 }.joined(separator: ":")
        appendTimeline(to: index, actorID: authorID, title: parentID == nil ? "Comment Added" : "Reply Added", detail: location.isEmpty ? trimmed : location)
        lastEvent = PullRequestEvent(actorID: authorID, title: "PR Comment Added", detail: pullRequests[index].title, notifies: true)
    }

    public func submitReview(prID: UUID, reviewerID: String, decision: PullRequestReviewDecision, summary: String) {
        guard let index = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        let review = PullRequestReview(reviewerID: reviewerID, decision: decision, summary: summary)
        pullRequests[index].reviews.append(review)
        switch decision {
        case .approve:
            pullRequests[index].status = .approved
        case .requestChanges, .reject:
            pullRequests[index].status = .rejected
        case .comment:
            if pullRequests[index].status == .draft || pullRequests[index].status == .closed || pullRequests[index].status == .merged {
                break
            }
            pullRequests[index].status = .open
        }
        appendTimeline(to: index, actorID: reviewerID, title: "Review Submitted", detail: decision.title)
        lastEvent = PullRequestEvent(actorID: reviewerID, title: "Review Submitted", detail: pullRequests[index].title, notifies: true)
    }

    public func updateStatus(prID: UUID, status: PullRequestStatus, actorID: String, mergeCommitID: UUID? = nil) {
        guard let index = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        pullRequests[index].status = status
        if let mergeCommitID { pullRequests[index].mergeCommitID = mergeCommitID }
        appendTimeline(to: index, actorID: actorID, title: "Status Changed", detail: status.rawValue.capitalized)
        lastEvent = PullRequestEvent(actorID: actorID, title: "PR Status Updated", detail: pullRequests[index].title, notifies: true)
    }

    public func close(prID: UUID, actorID: String) {
        updateStatus(prID: prID, status: .closed, actorID: actorID)
    }

    public func reopen(prID: UUID, actorID: String) {
        updateStatus(prID: prID, status: .open, actorID: actorID)
    }

    public func markMerged(prID: UUID, mergeCommitID: UUID, actorID: String) {
        updateStatus(prID: prID, status: .merged, actorID: actorID, mergeCommitID: mergeCommitID)
    }

    public func updateConflictSummary(prID: UUID, summary: String?, actorID: String) {
        guard let index = pullRequests.firstIndex(where: { $0.id == prID }) else { return }
        pullRequests[index].conflictSummary = summary
        appendTimeline(to: index, actorID: actorID, title: "Conflict Summary Updated", detail: summary ?? "No conflicts")
    }

    public func restoreState(pullRequests: [PullRequest]) {
        self.pullRequests = pullRequests
    }

    private func appendTimeline(to index: Int, actorID: String, title: String, detail: String) {
        pullRequests[index].timeline.insert(PullRequestTimelineEvent(actorID: actorID, title: title, detail: detail), at: 0)
    }
}
