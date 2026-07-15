import SwiftUI

@MainActor
struct DiscussionsView: View {
    let project: Project?

    // Category selection states
    @State private var selectedCategory = "Q&A"
    @State private var searchPattern = ""

    // Discussion threads states
    @State private var selectedThreadID: String?
    @State private var threads: [DiscussionThread] = []

    // Local-added replies to simulate instant comment updates on live threads
    @State private var localReplies: [String: [DiscussionReply]] = [:]
    @State private var replyText = ""

    // AI summary state
    @State private var isSummarizingThread = false
    @State private var aiSummaryText = ""

    // Fetch states
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var context: RepositoryContext {
        RepositoryContext.shared
    }

    private var filteredThreads: [DiscussionThread] {
        threads.filter {
            $0.category.localizedCaseInsensitiveContains(selectedCategory) &&
            (searchPattern.isEmpty || $0.title.localizedCaseInsensitiveContains(searchPattern))
        }
    }

    private var selectedThread: DiscussionThread? {
        guard let targetID = selectedThreadID else { return nil }
        return threads.first(where: { $0.id == targetID })
    }

    private var activeReplies: [DiscussionReply] {
        guard let thread = selectedThread else { return [] }
        return thread.replies + localReplies[thread.id, default: []]
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
            fetchDiscussions()
        }
        .onChange(of: context.connectedRepository) {
            fetchDiscussions()
        }
        .onChange(of: context.syncEventsCount) {
            fetchDiscussions()
        }
    }

    private var mainContent: some View {
        HSplitView {
            // Sidebar Pane 1: Category browser
            categoryPanel
                .frame(width: 180)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)

            // Split Pane 2: Thread list
            threadListPanel
                .frame(width: 250)
                .frame(maxHeight: .infinity)
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
            selectedThreadID = threads.first(where: { $0.category.localizedCaseInsensitiveContains(name) })?.id
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

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Fetching discussions...").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filteredThreads.isEmpty {
                VStack {
                    Spacer()
                    Text(errorMessage != nil ? "Error loading discussions" : "No threads in this category.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedThreadID) {
                    ForEach(filteredThreads) { thread in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title)
                                .font(.subheadline.bold())
                                .lineLimit(2)

                            HStack {
                                Text("by \(thread.author)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if thread.replies.contains(where: { $0.isAccepted }) {
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
            if let thread = selectedThread {
                VStack(alignment: .leading, spacing: 18) {
                    // Title block
                    VStack(alignment: .leading, spacing: 8) {
                        Text(thread.title)
                            .font(.title2.bold())

                        HStack {
                            Text("Posted by \(thread.author) in \(thread.category) • \(formatDateString(thread.date))")
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
                                    Text(formatDateString(reply.date)).font(.caption2).foregroundStyle(.secondary)
                                }

                                Text(reply.body)
                                    .font(.subheadline)

                                HStack {
                                    Button {
                                        // Upvote behavior
                                    } label: {
                                        Label("Upvote", systemImage: "arrow.up")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.plain)
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

    private func fetchDiscussions() {
        guard let repoStr = context.connectedRepository, !repoStr.isEmpty else { return }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else { return }
        let owner = String(parts[0])
        let repo = String(parts[1])

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await GitHubService.shared.fetchDiscussions(owner: owner, repo: repo)
                self.threads = fetched
                if selectedThreadID == nil || !fetched.contains(where: { $0.id == selectedThreadID }) {
                    selectedThreadID = fetched.first?.id
                }
            } catch {
                self.errorMessage = error.localizedDescription
                self.threads = []
            }
            isLoading = false
        }
    }

    private func executePostReply() {
        guard let thread = selectedThread else { return }
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = DiscussionReply(
            id: UUID().uuidString,
            author: "You",
            body: text,
            isAccepted: false,
            date: ISO8601DateFormatter().string(from: Date())
        )
        localReplies[thread.id, default: []].append(reply)
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

    private func formatDateString(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateStr) {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.unitsStyle = .full
            return relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return dateStr
    }
}
