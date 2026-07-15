import SwiftUI

@MainActor
struct IssueDetailView: View {
    let issue: GitHubIssue
    @Environment(\.dismiss) private var dismiss

    // Details tabs
    @State private var commentText = ""
    @State private var commentList: [IssueComment] = [
        IssueComment(author: "Jules", body: "We should focus on keeping memory allocations flat while rendering 10k items.", date: "2 days ago"),
        IssueComment(author: "reviewer-prime", body: "Agreed. Adding LazyVStack bounds inside ScrollView handles this perfectly.", date: "1 day ago")
    ]

    // AI Issue summarizing states
    @State private var isRunningAISummary = false
    @State private var aiSummaryText = ""

    struct IssueComment: Identifiable {
        let id = UUID()
        let author: String
        let body: String
        let date: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Issue #\(issue.number): \(issue.title)", systemImage: "exclamationmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // State Metadata block
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(issue.state.uppercased())
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.12))
                                    .foregroundStyle(.cyan)
                                    .cornerRadius(4)

                                Text("opened by \(issue.user.login) on \(issue.createdAt)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(issue.body ?? "No description provided.")
                                .font(.body)
                                .padding(.top, 6)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(6)
                    }

                    // Metadata Labels
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LABELS & MILESTONES")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Label("bug", systemImage: "tag.fill")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.1))
                                .foregroundStyle(.red)
                                .cornerRadius(4)

                            Label("v1.0.0", systemImage: "flag.fill")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.1))
                                .foregroundStyle(.purple)
                                .cornerRadius(4)

                            Label("Assignee: Jules", systemImage: "person.fill")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .foregroundStyle(.secondary)
                                .cornerRadius(4)
                        }
                    }

                    Divider()

                    // AI Issue Diagnostics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Issue Analyzer").font(.subheadline.bold())
                        Text("Let AI analyze the issue's scope, bug origin, and recommend a specific solution plan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            generateAIIssueSummary()
                        } label: {
                            Label(isRunningAISummary ? "Analyzing Bug..." : "Analyze Issue with AI", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunningAISummary)

                        if isRunningAISummary {
                            ProgressView().controlSize(.small)
                        }

                        if !aiSummaryText.isEmpty {
                            Text(aiSummaryText)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }

                    Divider()

                    // Comments feed thread
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CONVERSATION FEED")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        ForEach(commentList) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(comment.author).bold().font(.caption)
                                    Spacer()
                                    Text(comment.date).font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(comment.body)
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }

                        // Add comment form
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add comment").font(.caption.bold())
                            TextEditor(text: $commentText)
                                .frame(height: 80)
                                .border(Color.secondary.opacity(0.2), width: 1)

                            Button("Comment") {
                                executePostComment()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.cyan)
                            .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 550, height: 520)
    }

    private func executePostComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        commentList.append(IssueComment(author: "You", body: text, date: "Just now"))
        commentText = ""
    }

    private func generateAIIssueSummary() {
        isRunningAISummary = true
        aiSummaryText = ""

        let prompt = """
        You are an expert AI software debugging engineer.
        Analyze this issue description and prepare an automated bug report:
        - Title: \(issue.title)
        - Body: \(issue.body ?? "No description provided.")

        Provide exactly 3 lines:
        1. [Root Cause Analysis] Hypothesis of what is triggering the reported issue.
        2. [Correction Prescription] Code change suggestion.
        3. [Severity Rating] CVSS 3.1 Severity index evaluation (e.g. Medium 4.2).
        """

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiSummaryText = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiSummaryText = "AI analysis failed: \(error.localizedDescription)"
            }
            isRunningAISummary = false
        }
    }
}
