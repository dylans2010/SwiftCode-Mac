import SwiftUI

struct CollaborationCodeReviewView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String
    @State private var selectedCommitID: UUID?
    @State private var commentText = ""
    @State private var reviewerID = ""
    @State private var inlinePath = "Sources/Editor/CollabSession.swift"
    @State private var lineNumber = 42
    @State private var replyTargetID: UUID?

    var body: some View {
        List {
            Section("Commits Pending Review") {
                ForEach(manager.commits.commits(for: manager.branches.currentBranch.id)) { commit in
                    Button {
                        selectedCommitID = commit.id
                        manager.reviews.initiateReview(for: commit.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(commit.message).font(.headline)
                                Text(commit.authorID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(review(for: commit.id)?.status.rawValue.capitalized ?? "Pending")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }

            if let commit = selectedCommit {
                Section("Reviewer Assignment") {
                    HStack {
                        TextField("Reviewer Name", text: $reviewerID)
                        Button("Assign") {
                            manager.reviews.assignReviewer(reviewerID, to: commit.id, actorID: actorID)
                            reviewerID = ""
                        }
                        .disabled(reviewerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    ForEach(review(for: commit.id)?.reviewerIDs ?? [], id: \.self) { reviewer in
                        Label(reviewer, systemImage: "person.crop.circle.badge.checkmark")
                    }
                }

                Section("Inline Comments") {
                    TextField("File Path", text: $inlinePath)
                    Stepper("Line \(lineNumber)", value: $lineNumber, in: 1...999)
                    TextField(replyTargetID == nil ? "Add Comment" : "Reply In Thread", text: $commentText, axis: .vertical)
                        .lineLimit(2...5)
                    Button("Post") {
                        manager.reviews.addComment(to: commit.id, authorID: actorID, filePath: inlinePath, lineNumber: lineNumber, text: commentText, parentID: replyTargetID)
                        commentText = ""
                        replyTargetID = nil
                    }
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    ForEach(rootComments(for: commit.id)) { comment in
                        VStack(alignment: .leading, spacing: 6) {
                            commentView(comment)
                            ForEach(replies(for: comment, commitID: commit.id)) { reply in
                                commentView(reply)
                                    .padding(.leading, 16)
                            }
                            Button("Reply") { replyTargetID = comment.id }
                                .font(.caption)
                        }
                    }
                }

                Section("Decision") {
                    Button {
                        manager.reviews.approveReview(for: commit.id, actorID: actorID)
                    } label: {
                        Label("Approve", systemImage: "checkmark.seal.fill")
                    }
                    .tint(.green)

                    Button {
                        manager.reviews.requestChanges(for: commit.id, actorID: actorID)
                    } label: {
                        Label("Request Changes", systemImage: "arrow.uturn.backward.circle.fill")
                    }
                    .tint(.orange)

                    Button(role: .destructive) {
                        manager.reviews.rejectReview(for: commit.id, actorID: actorID)
                    } label: {
                        Label("Reject", systemImage: "xmark.seal.fill")
                    }
                }

                Section("Review History") {
                    ForEach(review(for: commit.id)?.history ?? []) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.message).font(.headline)
                            if let filePath = entry.filePath {
                                Text(filePath).font(.caption)
                            }
                            Text("\(entry.actorID) • \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Code Reviews")
        .onAppear {
            if selectedCommitID == nil {
                selectedCommitID = manager.commits.commits(for: manager.branches.currentBranch.id).first?.id
            }
        }
    }

    private var selectedCommit: Commit? {
        guard let selectedCommitID else { return nil }
        return manager.commits.commits.first(where: { $0.id == selectedCommitID })
    }

    private func review(for commitID: UUID) -> CodeReview? {
        manager.reviews.reviews[commitID]
    }

    private func rootComments(for commitID: UUID) -> [ReviewComment] {
        (review(for: commitID)?.comments ?? []).filter { $0.parentID == nil }
    }

    private func replies(for comment: ReviewComment, commitID: UUID) -> [ReviewComment] {
        (review(for: commitID)?.comments ?? []).filter { $0.parentID == comment.id }
    }

    private func commentView(_ comment: ReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(comment.filePath):\(comment.lineNumber)")
                .font(.caption.bold())
            Text(comment.text)
            Text(comment.authorID)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
