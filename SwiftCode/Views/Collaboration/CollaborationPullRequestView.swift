import SwiftUI

struct CollaborationPullRequestView: View {
    @ObservedObject var manager: CollaborationManager
    let actorID: String

    @State private var showingCreatePR = false
    @State private var selectedPRID: UUID?
    @State private var commentText = ""
    @State private var reviewerID = ""
    @State private var reviewSummary = ""
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var selectedCommitToLink: UUID?
    @State private var inlinePath = "Sources/Editor/CollabSession.swift"
    @State private var inlineLine = 1
    @State private var selectedThreadParentID: UUID?
    @State private var isSubmitting = false
    @State private var feedback: ViewFeedback?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pullRequestsList

                if let pr = selectedPR {
                    prDetailView(pr)
                }
            }
            .padding()
        }
        .background(Color.clear)
        .navigationTitle("Pull Requests")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreatePR = true } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let feedback {
                Label(feedback.message, systemImage: feedback.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showingCreatePR) {
            PRCreateView(manager: manager, actorID: actorID)
        }
        .onAppear {
            if selectedPRID == nil {
                selectedPRID = manager.pullRequests.pullRequests.first?.id
                if let pr = selectedPR { syncEditorFields(with: pr) }
            }
        }
    }

    private var pullRequestsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Pull Requests")
                .font(.headline)
                .foregroundStyle(.white)

            if manager.pullRequests.pullRequests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No Pull Requests")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            ForEach(manager.pullRequests.pullRequests) { pr in
                Button {
                    withAnimation {
                        selectedPRID = pr.id
                        syncEditorFields(with: pr)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(pr.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Spacer()
                            statusBadge(pr.status)
                        }

                        Text(pr.description.isEmpty ? "No Description" : pr.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.circle")
                                Text(pr.authorID)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "shippingbox")
                                Text("\(pr.linkedCommitIDs.count)")
                            }
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                Text("\(pr.comments.count)")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(selectedPRID == pr.id ? Color.blue.opacity(0.2) : Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selectedPRID == pr.id ? Color.blue.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func prDetailView(_ pr: PullRequest) -> some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Information")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(spacing: 12) {
                    TextField("Title", text: $editTitle)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    TextField("Description", text: $editDescription, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .lineLimit(3...8)

                    Button {
                        manager.pullRequests.editPullRequest(prID: pr.id, title: editTitle, description: editDescription, actorID: actorID)
                        feedback = .success("Pull request details updated.")
                    } label: {
                        Label("Save Changes", systemImage: "square.and.pencil")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                summaryGrid(for: pr)

                if let summary = pr.conflictSummary, !summary.isEmpty {
                    Label(summary, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 16) {
                Text("Reviews & Actions")
                    .font(.headline)

                HStack {
                    actionIcon(title: "Approve", icon: "checkmark.circle.fill", color: .green) {
                        manager.pullRequests.submitReview(prID: pr.id, reviewerID: actorID, decision: .approve, summary: reviewSummary.isEmpty ? "Approved" : reviewSummary)
                    }
                    actionIcon(title: "Changes", icon: "arrow.uturn.left.circle.fill", color: .orange) {
                        manager.pullRequests.submitReview(prID: pr.id, reviewerID: actorID, decision: .requestChanges, summary: reviewSummary.isEmpty ? "Requested Changes" : reviewSummary)
                    }
                    actionIcon(title: "Merge", icon: "arrow.triangle.merge", color: .purple) {
                        manager.merge(branch: pr.sourceBranchID, into: pr.targetBranchID, actorID: actorID, pullRequestID: pr.id)
                    }
                }

                TextField("Review Summary", text: $reviewSummary)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    if pr.status == .closed {
                        Button("Reopen PR") { manager.pullRequests.reopen(prID: pr.id, actorID: actorID) }
                            .buttonStyle(.bordered)
                    } else if pr.status != .merged {
                        Button("Close PR", role: .destructive) { manager.pullRequests.close(prID: pr.id, actorID: actorID) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 16) {
                Text("Reviewers & Linked Commits")
                    .font(.headline)
                HStack {
                    TextField("Assign Reviewer", text: $reviewerID)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button("Assign") {
                        manager.pullRequests.assignReviewer(reviewerID, to: pr.id, actorID: actorID)
                        reviewerID = ""
                    }
                    .disabled(reviewerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !pr.reviewerIDs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(pr.reviewerIDs, id: \.self) { reviewer in
                                Label(reviewer, systemImage: "person.badge.shield.checkmark")
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Linked Commits")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    Picker("Link commit", selection: $selectedCommitToLink) {
                        Text("Select a commit to link").tag(UUID?.none)
                        ForEach(manager.commits.commits(for: pr.sourceBranchID)) { commit in
                            Text(commit.message).tag(UUID?.some(commit.id))
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Link Commit") {
                        if let selectedCommitToLink {
                            manager.pullRequests.linkCommit(selectedCommitToLink, to: pr.id, actorID: actorID)
                        }
                    }
                    .disabled(selectedCommitToLink == nil)
                    .buttonStyle(.bordered)

                    ForEach(pr.linkedCommitIDs, id: \.self) { commitID in
                        if let commit = manager.commits.commits.first(where: { $0.id == commitID }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(commit.message).font(.subheadline.bold())
                                    Text("\(commit.authorID) • \(commit.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "link")
                                    .foregroundStyle(.blue)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 16) {
                Text("Diff Preview")
                    .font(.headline)

                ForEach(Array(prDiffEntries(pr).enumerated()), id: \.offset) { _, entry in
                    NavigationLink {
                        CollaborationDiffViewerView(diff: entry.value)
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundStyle(.blue)
                            Text(entry.key)
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            VStack(alignment: .leading, spacing: 16) {
                Text("Comments")
                    .font(.headline)

                VStack(spacing: 12) {
                    TextField("File Path", text: $inlinePath)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Stepper("Line \(inlineLine)", value: $inlineLine, in: 1...2000)
                        .font(.caption)

                    TextField("Comment", text: $commentText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .lineLimit(2...4)

                    Button {
                        isSubmitting = true
                        manager.pullRequests.addComment(to: pr.id, authorID: actorID, text: commentText, filePath: inlinePath, lineNumber: inlineLine, parentID: selectedThreadParentID)
                        commentText = ""
                        selectedThreadParentID = nil
                        isSubmitting = false
                    } label: {
                        Label(selectedThreadParentID == nil ? "Post Comment" : "Reply", systemImage: "paperplane.fill")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .disabled(commentText.isEmpty || isSubmitting)
                }

                VStack(spacing: 12) {
                    ForEach(rootComments(for: pr)) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            commentCard(comment)
                            ForEach(replies(for: comment, in: pr)) { reply in
                                commentCard(reply)
                                    .padding(.leading, 20)
                            }
                            Button("Reply") { selectedThreadParentID = comment.id }
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }

    private var selectedPR: PullRequest? {
        guard let selectedPRID else { return nil }
        return manager.pullRequests.pullRequests.first(where: { $0.id == selectedPRID })
    }

    private func syncEditorFields(with pr: PullRequest) {
        editTitle = pr.title
        editDescription = pr.description
    }

    private func prDiffEntries(_ pr: PullRequest) -> [(key: String, value: String)] {
        let linked = manager.commits.commits.filter { pr.linkedCommitIDs.contains($0.id) }
        let changes = linked.flatMap { $0.changes.map { ($0.key, $0.value) } }
        let grouped = Dictionary(grouping: changes, by: { $0.0 })
        return grouped.map { key, value in
            (key, value.map { $0.1 }.joined(separator: "\n"))
        }.sorted { $0.key < $1.key }
    }

    private func rootComments(for pr: PullRequest) -> [PullRequestComment] {
        pr.comments.filter { $0.parentID == nil }
    }

    private func replies(for comment: PullRequestComment, in pr: PullRequest) -> [PullRequestComment] {
        pr.comments.filter { $0.parentID == comment.id }
    }

    private func commentCard(_ comment: PullRequestComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.authorID).font(.caption.bold()).foregroundStyle(.blue)
                Spacer()
                if let filePath = comment.filePath, let lineNumber = comment.lineNumber {
                    Text("\(filePath):\(lineNumber)").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            Text(comment.text).font(.caption).foregroundStyle(.white)
            Text(comment.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusBadge(_ status: PullRequestStatus) -> some View {
        Text(status.rawValue.capitalized)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusColor(status).opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: PullRequestStatus) -> Color {
        switch status {
        case .open: return .green
        case .draft: return .gray
        case .approved: return .blue
        case .rejected: return .red
        case .merged: return .purple
        case .closed: return .orange
        }
    }

    private func actionIcon(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption.bold())
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func summaryGrid(for pr: PullRequest) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            summaryRow(title: "Source", value: branchName(pr.sourceBranchID))
            summaryRow(title: "Target", value: branchName(pr.targetBranchID))
            summaryRow(title: "Commits", value: "\(pr.linkedCommitIDs.count)")
            summaryRow(title: "Status", value: pr.status.rawValue.capitalized)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func summaryRow(title: String, value: String) -> some View {
        GridRow {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .foregroundStyle(.white)
        }
    }

    private func branchName(_ id: UUID) -> String {
        manager.branches.branches.first(where: { $0.id == id })?.name ?? "Unknown"
    }
}

private struct MultipleSelectionRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .green : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ViewFeedback: Equatable {
    let message: String
    let isError: Bool

    static func success(_ message: String) -> Self { .init(message: message, isError: false) }
    static func error(_ message: String) -> Self { .init(message: message, isError: true) }
}
