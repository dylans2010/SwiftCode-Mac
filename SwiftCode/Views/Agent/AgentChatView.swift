import SwiftUI

public struct AgentChatView: View {
    @Environment(AgentViewModel.self) var viewModel
    @State private var showChecklist = true
    @State private var showHistorySheet = false

    public init() {}

    public var body: some View {
        HSplitView {
            // Column 1: Conversation Area (Takes majority space)
            VStack(spacing: 0) {
                // Mode Segmented Picker and Controls
                HStack(spacing: 12) {
                    // Chat History Browser Button (replaces sidebar left toggle)
                    Button {
                        showHistorySheet = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Browse previous conversations")

                    // Segmented Picker for Chat/Agent Mode
                    Picker("Mode", selection: Binding(
                        get: { viewModel.session.mode },
                        set: { newMode in
                            withAnimation(.spring()) {
                                viewModel.session.mode = newMode
                            }
                        }
                    )) {
                        ForEach(AgentChatMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)

                    Spacer()

                    // Active model & provider indicator
                    HStack(spacing: 4) {
                        Image(systemName: FoundationModels.shared.isEnabled ? "apple.logo" : "network")
                            .font(.system(size: 11))
                            .foregroundStyle(FoundationModels.shared.isEnabled ? .orange : .purple)
                        Text(FoundationModels.shared.isEnabled ? FoundationModels.shared.selectedModel.rawValue : AppSettings.shared.selectedAssistModelID)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)

                    Button {
                        withAnimation(.spring()) {
                            showChecklist.toggle()
                        }
                    } label: {
                        Image(systemName: "checklist")
                            .foregroundColor(showChecklist ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Plan & Tasks")
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Conversation Message List
                AgentMessageListView(messages: viewModel.session.messages, viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Typing/Assistant Indicator
                if viewModel.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                        Text(viewModel.session.turnState == .executingTools ? "Executing skills..." : "AI is thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.05))
                    .transition(.opacity)
                }

                // Visual Error Banner Overlay
                if case .failed(let error) = viewModel.session.turnState {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Request Failed")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.red)
                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                withAnimation(.spring()) {
                                    viewModel.session.turnState = .idle
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Spacer()
                            Button("Dismiss") {
                                withAnimation(.spring()) {
                                    viewModel.session.turnState = .idle
                                }
                            }
                            .buttonStyle(.bordered)

                            if let lastUserMessage = viewModel.session.messages.last(where: { $0.role == .user }),
                               let firstContent = lastUserMessage.content.first,
                               case .text(let prompt) = firstContent {
                                Button("Retry") {
                                    let retryPrompt = prompt
                                    withAnimation(.spring()) {
                                        viewModel.session.turnState = .idle
                                        Task {
                                            await viewModel.sendUserMessage(retryPrompt)
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.red.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.red.opacity(0.2), lineWidth: 1)
                    )
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Input Bar (Attachments picker + textfield + Send)
                AgentInputBarView(viewModel: viewModel)
            }
            .frame(minWidth: 400)
            .layoutPriority(1) // High layout priority ensures Center is highest priority and takes majority space!

            // Column 2: Right "Plan & Tasks" Checklist Inspector
            if showChecklist {
                VStack(spacing: 0) {
                    HStack {
                        Label("Plan & Tasks", systemImage: "checklist")
                            .font(.headline)
                        Spacer()
                        Button {
                            withAnimation(.spring()) {
                                showChecklist = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    AgentChecklistView(state: viewModel.session.checklist)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 350)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .sheet(isPresented: $showHistorySheet) {
            ChatHistoryBrowserSheet(viewModel: viewModel, isPresented: $showHistorySheet)
        }
        .macDesktopOptimized()
    }
}

// MARK: - ChatHistoryBrowserSheet

struct ChatHistoryBrowserSheet: View {
    @Bindable var viewModel: AgentViewModel
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var sortOption: SortOption = .recent

    // For Rename alert
    @State private var sessionToRename: AgentSession? = nil
    @State private var renameText = ""
    @State private var showingRenameAlert = false

    enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case alphabetical = "Name"
        case pinned = "Pinned First"

        var id: String { self.rawValue }
    }

    var sortedAndFilteredSessions: [AgentSession] {
        var filtered = viewModel.sessions
        if !searchText.isEmpty {
            filtered = filtered.filter { s in
                if let title = s.title, title.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                return s.firstUserMessageText.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOption {
        case .recent:
            filtered.sort { $0.lastModified > $1.lastModified }
        case .alphabetical:
            filtered.sort { $0.firstUserMessageText.localizedCaseInsensitiveCompare($1.firstUserMessageText) == .orderedAscending }
        case .pinned:
            filtered.sort {
                if $0.isPinned == $1.isPinned {
                    return $0.lastModified > $1.lastModified
                }
                return $0.isPinned && !$1.isPinned
            }
        }

        return filtered
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Conversation Browser")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 15)

            Divider()

            // Search & Sort Bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search previous chats...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Picker("Sort", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Button {
                    viewModel.startNewSession(mode: viewModel.session.mode)
                    isPresented = false
                } label: {
                    Label("New Chat", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(15)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))

            Divider()

            // Document Browser List
            ScrollView {
                VStack(spacing: 10) {
                    if sortedAndFilteredSessions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No Conversations Found")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(sortedAndFilteredSessions) { s in
                            let isSelected = s.id == viewModel.session.id

                            HStack(alignment: .center, spacing: 14) {
                                // Pinned status indicator or pin button
                                Button {
                                    viewModel.togglePinSession(s)
                                } label: {
                                    Image(systemName: s.isPinned ? "pin.fill" : "pin")
                                        .foregroundStyle(s.isPinned ? .orange : .secondary)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .help(s.isPinned ? "Unpin" : "Pin")

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(s.firstUserMessageText)
                                            .font(.body)
                                            .fontWeight(isSelected ? .bold : .regular)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(s.lastModified.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    HStack(spacing: 8) {
                                        // Mode Badge
                                        let isAgent = (s.mode == .agent)
                                        let badgeColor: Color = isAgent ? .purple : .blue
                                        Text(s.mode.rawValue.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(badgeColor.opacity(0.15))
                                            .foregroundStyle(badgeColor)
                                            .cornerRadius(3)

                                        if isSelected {
                                            Text("Active")
                                                .font(.system(size: 8, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.15))
                                                .foregroundStyle(.green)
                                                .cornerRadius(3)
                                        }

                                        Spacer()
                                    }
                                }

                                // Operations actions
                                HStack(spacing: 12) {
                                    Button {
                                        sessionToRename = s
                                        renameText = s.title ?? ""
                                        showingRenameAlert = true
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Rename")

                                    Button {
                                        viewModel.duplicateSession(s)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .foregroundStyle(.purple)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Duplicate")

                                    Button {
                                        viewModel.deleteSession(s)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Delete")
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectSession(s)
                                isPresented = false
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 580, height: 480)
        .sheet(isPresented: $showingRenameAlert) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename Conversation")
                    .font(.headline)
                    .fontWeight(.bold)

                TextField("Enter conversation name...", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        if let s = sessionToRename {
                            viewModel.renameSession(id: s.id, newTitle: renameText)
                        }
                        showingRenameAlert = false
                    }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        showingRenameAlert = false
                    }
                    .buttonStyle(.bordered)

                    Button("Rename") {
                        if let s = sessionToRename {
                            viewModel.renameSession(id: s.id, newTitle: renameText)
                        }
                        showingRenameAlert = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
    }
}
