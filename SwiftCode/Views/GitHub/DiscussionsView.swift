import SwiftUI

@MainActor
struct DiscussionsView: View {
    let project: Project?

    // Category selection states
    @State private var selectedCategory = "Q&A"
    @State private var searchPattern = ""

    // Discussion threads states
    @State private var selectedThreadID: UUID?
    @State private var threads: [DiscussionThread] = [
        DiscussionThread(
            title: "How to minimize Redraw Cycles in SwiftUI HSplitView?",
            author: "dev-explorer",
            category: "Q&A",
            body: "I am building a native macOS multi-column split layout and noticed some lag during split divider drags. What is the recommended frame constraint pattern?",
            votes: 24,
            repliesCount: 3,
            hasAcceptedAnswer: true,
            date: "3 days ago"
        ),
        DiscussionThread(
            title: "Proposing Modular Plugin Extension Architecture",
            author: "Jules",
            category: "Ideas",
            body: "We could load dynamic bundles compiled with Xcode in private developer directories to support custom linters and code suggestions.",
            votes: 42,
            repliesCount: 8,
            hasAcceptedAnswer: false,
            date: "2 days ago"
        ),
        DiscussionThread(
            title: "Announcing SwiftCode v1.1.0 Stable Rollout!",
            author: "DevOps Bot",
            category: "Announcements",
            body: "We have finalized workflow pipelines, multi-window split structures, and native git blame annotations! Update your workspaces today.",
            votes: 56,
            repliesCount: 2,
            hasAcceptedAnswer: false,
            date: "1 day ago"
        )
    ]

    // Active replies list
    @State private var replyText = ""
    @State private var activeReplies: [DiscussionReply] = [
        DiscussionReply(author: "Jules", body: "Set the .layoutPriority() modifier explicitly on primary detail containers to prevent frame layout recalculation during drags.", isAccepted: true, date: "2 days ago"),
        DiscussionReply(author: "reviewer-prime", body: "Also consider using an underlying NSSplitViewController wrapping NSHostingControllers for optimal performance.", isAccepted: false, date: "1 day ago")
    ]

    // AI summary state
    @State private var isSummarizingThread = false
    @State private var aiSummaryText = ""

    private var context: RepositoryContext {
        RepositoryContext.shared
    }

    struct DiscussionThread: Identifiable {
        let id = UUID()
        let title: String
        let author: String
        let category: String
        let body: String
        var votes: Int
        let repliesCount: Int
        let hasAcceptedAnswer: Bool
        let date: String
    }

    struct DiscussionReply: Identifiable {
        let id = UUID()
        let author: String
        let body: String
        var isAccepted: Bool
        let date: String
    }

    var body: some View {
        VStack(spacing: 0) {
            if context.displayMode == .connectedRepository && context.connectedRepository == nil {
                disconnectedPlaceholder
            } else {
                mainContent
            }
        }
        .onAppear {
            if selectedThreadID == nil {
                selectedThreadID = threads.first(where: { $0.category == selectedCategory })?.id
            }
        }
    }

    private var mainContent: some View {
        HSplitView {
            // Sidebar Pane 1: Category browser
            categoryPanel
                .frame(width: 180, maxHeight: .infinity)
                .layoutPriority(1)

            // Split Pane 2: Thread list
            threadListPanel
                .frame(width: 250, maxHeight: .infinity)
                .layoutPriority(2)

            // Split Pane 3: Selected thread workspace
            threadDetailWorkspacePanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(3)
        }
    }

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CATEGORIES")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.04))

            Divider()

            List {
                categoryRow(name: "Announcements", icon: "megaphone.fill")
                categoryRow(name: "Q&A", icon: "questionmark.bubble.fill")
                categoryRow(name: "Ideas", icon: "lightbulb.fill")
                categoryRow(name: "General", icon: "bubble.left.and.bubble.right.fill")
                categoryRow(name: "Show and Tell", icon: "eye.fill")
            }
            .listStyle(.plain)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func categoryRow(name: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.purple)
                .frame(width: 16)
            Text(name)
                .font(.subheadline)
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCategory = name
            selectedThreadID = threads.first(where: { $0.category == name })?.id
            aiSummaryText = ""
        }
        .listRowBackground(selectedCategory == name ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private var threadListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search threads...", text: $searchPattern)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(8)

            Divider()

            let filtered = threads.filter {
                $0.category == selectedCategory &&
                (searchPattern.isEmpty || $0.title.localizedCaseInsensitiveContains(searchPattern))
            }

            if filtered.isEmpty {
                Text("No threads in this category.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(selection: $selectedThreadID) {
                    ForEach(filtered) { thread in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title)
                                .font(.subheadline.bold())
                                .lineLimit(2)

                            HStack {
                                Text("by \(thread.author)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if thread.hasAcceptedAnswer {
                                    Label("Resolved", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .tag(thread.id)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var threadDetailWorkspacePanel: some View {
        ScrollView {
            if let targetID = selectedThreadID,
               let thread = threads.first(where: { $0.id == targetID }) {
                VStack(alignment: .leading, spacing: 18) {
                    // Title block
                    VStack(alignment: .leading, spacing: 8) {
                        Text(thread.title)
                            .font(.title2.bold())

                        HStack {
                            Text("Posted by \(thread.author) in \(thread.category) • \(thread.date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            HStack(spacing: 8) {
                                Label("\(thread.votes)", systemImage: "arrow.up")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundStyle(.purple)
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Divider()

                    // Thread Body
                    Text(thread.body)
                        .font(.body)
                        .textSelection(.enabled)

                    Divider()

                    // AI Thread summarization
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Thread Summarizer").font(.subheadline.bold())
                        Text("Synthesize thread consensus and highlight accepted answers or action points.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            summarizeDiscussionThread(thread)
                        } label: {
                            Label(isSummarizingThread ? "Synthesizing consensus..." : "Summarize Thread with AI", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSummarizingThread)

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

                    // Replies Catalog
                    VStack(alignment: .leading, spacing: 12) {
                        Text("REPLIES (\(activeReplies.count))")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        ForEach(activeReplies) { reply in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(reply.author).bold().font(.caption)
                                    Spacer()
                                    if reply.isAccepted {
                                        Label("ACCEPTED ANSWER", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.green)
                                    }
                                    Text(reply.date).font(.caption2).foregroundStyle(.secondary)
                                }

                                Text(reply.body)
                                    .font(.subheadline)

                                HStack {
                                    Button {
                                        // Vote mock
                                    } label: {
                                        Label("Upvote", systemImage: "arrow.up")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)

                                    if !reply.isAccepted && thread.author == "You" {
                                        Button("Accept Answer") {
                                            // Accept mock
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                    }
                                }
                                .padding(.top, 2)
                            }
                            .padding(10)
                            .background(reply.isAccepted ? Color.green.opacity(0.04) : Color.secondary.opacity(0.02))
                            .cornerRadius(6)
                            Divider()
                        }

                        // Add Reply Editor Form
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Post a Reply").font(.caption.bold())
                            TextEditor(text: $replyText)
                                .frame(height: 80)
                                .border(Color.secondary.opacity(0.2), width: 1)

                            Button("Reply") {
                                executePostReply()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .padding(20)
            } else {
                ContentUnavailableView(
                    "No Thread Focused",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select a discussion thread from the browser list on the left to read posts and comments.")
                )
                .padding()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func executePostReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        activeReplies.append(DiscussionReply(author: "You", body: text, isAccepted: false, date: "Just now"))
        replyText = ""
    }

    private var disconnectedPlaceholder: some View {
        GitHubEmptyStateView(
            title: "No Repository Associated",
            description: "A GitHub repository must first be associated with this project to view and manage Discussions.",
            systemImage: "bubble.left.and.bubble.right.fill",
            accentColor: .orange,
            actionTitle: "Configure Repository Association"
        ) {
            RepositoryContext.shared.showingSetRepoSheet = true
        }
    }

    private func summarizeDiscussionThread(_ thread: DiscussionThread) {
        isSummarizingThread = true
        aiSummaryText = ""

        let prompt = """
        You are an expert AI thread facilitator. Analyze this GitHub Discussion:
        - Category: \(thread.category)
        - Title: \(thread.title)
        - Body: \(thread.body)
        - Accepted Answer: \(activeReplies.first(where: { $0.isAccepted })?.body ?? "None")

        Synthesize the conversation into exactly 3 lines:
        1. [Overview] Main problem/idea discussed.
        2. [Consensus Solution] Propose or highlight the accepted/recommended solution.
        3. [Next Action] Action items for the repository team.
        """

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiSummaryText = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiSummaryText = "Consensus synthesis failed: \(error.localizedDescription)"
            }
            isSummarizingThread = false
        }
    }
}
