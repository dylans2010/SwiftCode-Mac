import SwiftUI

@MainActor
struct PullRequestDetailView: View {
    let pr: GitHubPullRequest
    @Environment(\.dismiss) private var dismiss

    // Details view segment tabs
    @State private var activeTab: DetailTab = .conversation

    // Conversation states
    @State private var timelineComments: [TimelineComment] = [
        TimelineComment(author: "reviewer-prime", body: "Could you optimize the rendering path in the Canvas drawing method?", type: .reviewComment, date: "Yesterday at 4:12 PM"),
        TimelineComment(author: "Jules", body: "Sure, streamlined the frame counts and minimized view redraw boundaries.", type: .commit, date: "Today at 10:45 AM")
    ]

    // Files Changed states
    @State private var selectedFileIdx = 0
    @State private var filesModified = [
        PRFile(path: "Sources/SwiftCode/Views/GitHub/CommitsView.swift", status: "modified", additions: 142, deletions: 34),
        PRFile(path: "Sources/SwiftCode/Views/GitHub/SourceControlView.swift", status: "modified", additions: 24, deletions: 8),
        PRFile(path: "Tests/SwiftCodeTests/CommitsViewTests.swift", status: "added", additions: 44, deletions: 0)
    ]

    // AI Review states
    @State private var isRunningAIReview = false
    @State private var aiReviewSummaryText = ""

    enum DetailTab: String, CaseIterable, Identifiable {
        case conversation = "Conversation"
        case files = "Files Changed"
        case aiReviews = "AI Review Assistant"

        var id: String { rawValue }
    }

    struct PRFile: Identifiable {
        let id = UUID()
        let path: String
        let status: String
        let additions: Int
        let deletions: Int
    }

    struct TimelineComment: Identifiable {
        let id = UUID()
        let author: String
        let body: String
        let type: CommentType
        let date: String

        enum CommentType {
            case reviewComment
            case commit
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("PR #\(pr.number): \(pr.title)", systemImage: "arrow.triangle.pull")
                    .font(.headline)
                    .foregroundStyle(.green)

                Spacer()

                // Tabs Switcher
                Picker("Tabs", selection: $activeTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 380)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Active Tab Pane Switcher
            switch activeTab {
            case .conversation:
                conversationPane
            case .files:
                filesChangedPane
            case .aiReviews:
                aiReviewsPane
            }
        }
        .frame(width: 650, height: 560)
    }

    // MARK: - Conversation Tab Pane

    private var conversationPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Status Header section
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(pr.state.uppercased())
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.12))
                                .foregroundStyle(.green)
                                .cornerRadius(4)

                            Text("opened by \(pr.user.login) on \(pr.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(pr.body ?? "No description provided.")
                            .font(.body)
                            .padding(.top, 6)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(6)
                }

                // Reviews & Approvals Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("REVIEWS & APPROVALS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    HStack {
                        Label("Approved by reviewer-prime", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.green.opacity(0.06))
                    .cornerRadius(4)
                }

                // CI / Build checks
                VStack(alignment: .leading, spacing: 8) {
                    Text("BUILD CHECK STATUS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("CI Pipeline: All checks passed (3 successful)")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.04))
                    .cornerRadius(4)
                }

                // Conflict and Merge controls
                VStack(alignment: .leading, spacing: 10) {
                    Text("MERGE INTEGRATION CONTROLS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("This branch has no conflicts with the base branch.")
                            .font(.subheadline)
                    }

                    HStack(spacing: 12) {
                        Button {
                            // Merge PR execution mock
                        } label: {
                            Label("Merge Pull Request", systemImage: "arrow.merge")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button {
                            // Squash mock
                        } label: {
                            Text("Squash & Merge")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            // Rebase mock
                        } label: {
                            Text("Rebase & Merge")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(Color.green.opacity(0.04))
                .cornerRadius(6)

                // Conversation Timeline (comments and commits)
                VStack(alignment: .leading, spacing: 10) {
                    Text("TIMELINE ACTIVITY")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)

                    ForEach(timelineComments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: comment.type == .commit ? "arrow.triangle.branch" : "bubble.left.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(comment.author).bold()
                                    .font(.caption)

                                Spacer()

                                Text(comment.date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(comment.body)
                                .font(.subheadline)
                                .padding(.leading, 18)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Files Changed Tab Pane

    private var filesChangedPane: some View {
        HSplitView {
            // Left list files
            List(0..<filesModified.count, id: \.self) { idx in
                let file = filesModified[idx]
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((file.path as NSString).lastPathComponent)
                            .font(.subheadline.bold())
                        Text(file.path)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("+\(file.additions)").foregroundStyle(.green).font(.caption.bold())
                        Text("-\(file.deletions)").foregroundStyle(.red).font(.caption.bold())
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedFileIdx = idx
                }
                .listRowBackground(selectedFileIdx == idx ? Color.accentColor.opacity(0.1) : Color.clear)
            }
            .frame(width: 220)

            // Right inline diff display
            VStack(alignment: .leading, spacing: 0) {
                let activeFile = filesModified[selectedFileIdx]
                Text("Diff for \(activeFile.path)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        diffLine(text: "@@ -14,10 +14,24 @@ class CommitsView {", type: .hunk)
                        diffLine(text: " class CommitsView: View {", type: .normal)
                        diffLine(text: "     var gitViewModel: GitViewModel", type: .normal)
                        diffLine(text: "-    @State private var selectedCommit: GitCommit?", type: .deleted)
                        diffLine(text: "+    @State private var selectedCommitID: String?", type: .added)
                        diffLine(text: "+    @State private var searchKeyword = \"\"", type: .added)
                        diffLine(text: " ", type: .normal)
                        diffLine(text: "     var body: some View {", type: .normal)
                        diffLine(text: "         HSplitView {", type: .normal)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    enum DiffLineType {
        case hunk
        case normal
        case added
        case deleted
    }

    private func diffLine(text: String, type: DiffLineType) -> some View {
        Text(text)
            .foregroundStyle(diffLineColor(type))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(diffLineBgColor(type))
    }

    private func diffLineColor(_ type: DiffLineType) -> Color {
        switch type {
        case .hunk: return .cyan
        case .normal: return .white.opacity(0.8)
        case .added: return .green
        case .deleted: return .red
        }
    }

    private func diffLineBgColor(_ type: DiffLineType) -> Color {
        switch type {
        case .hunk: return .cyan.opacity(0.12)
        case .normal: return .clear
        case .added: return .green.opacity(0.1)
        case .deleted: return .red.opacity(0.1)
        }
    }

    // MARK: - AI Reviews Tab Pane

    private var aiReviewsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AI Code Reviewer & Assistant")
                    .font(.headline)

                Text("Automate pull request reviews! AI reads files changed in this branch, reviews coding patterns against macOS standards, and drafts summaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    generateAIPRReview()
                } label: {
                    Label(isRunningAIReview ? "Conducting Code Audits..." : "Run AI Pull Request Review Audit", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isRunningAIReview)

                if isRunningAIReview {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("AI evaluation running on modified diff files...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !aiReviewSummaryText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Code Audit Summary Report:")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        Text(aiReviewSummaryText)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            }
            .padding(24)
        }
    }

    private func generateAIPRReview() {
        isRunningAIReview = true
        aiReviewSummaryText = ""

        let prompt = """
        You are an AI Pull Request review auditor. Review the following PR state details:
        - PR Number: #\(pr.number)
        - Title: \(pr.title)
        - Description: \(pr.body ?? "No description provided.")
        - Files modified: Sources/SwiftCode/Views/GitHub/CommitsView.swift, Sources/SwiftCode/Views/GitHub/SourceControlView.swift

        Generate an automated review report of exactly 4 lines:
        1. [Overall Assessment] Quick rating (e.g., Looks Good, Requires changes) and summary.
        2. [Suggested Changes] Highlight a minor point (e.g., suggest adding documentation comments or performance parameters).
        3. [Gaps/Risks] Assessment of dependencies or conflicts.
        4. [Review Approval Verdict] Safe to Merge recommendation.
        """

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiReviewSummaryText = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiReviewSummaryText = "AI review error: \(error.localizedDescription)"
            }
            isRunningAIReview = false
        }
    }
}
