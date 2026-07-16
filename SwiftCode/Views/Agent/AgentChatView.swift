import SwiftUI

public struct AgentChatView: View {
    @Environment(AgentViewModel.self) var viewModel
    @State private var showSidebar = true
    @State private var showChecklist = true
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        HSplitView {
            // Column 1: Left Sidebar (Conversation History)
            if showSidebar {
                VStack(spacing: 0) {
                    HStack {
                        // Search field for filtering sessions
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search Chats...", text: $searchText)
                            .textFieldStyle(.plain)

                        Button {
                            withAnimation(.spring()) {
                                viewModel.startNewSession(mode: viewModel.session.mode)
                            }
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .help("New Chat")
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .padding(8)

                    Divider()

                    // Sessions List
                    List(selection: Binding(
                        get: { viewModel.session.id },
                        set: { id in
                            if let s = viewModel.sessions.first(where: { $0.id == id }) {
                                viewModel.selectSession(s)
                            }
                        }
                    )) {
                        let filteredSessions = viewModel.sessions.filter { s in
                            searchText.isEmpty || s.messages.compactMap { content -> String? in
                                if case .text(let t) = content { return t }
                                return nil
                            }.joined(separator: " ").localizedCaseInsensitiveContains(searchText)
                        }

                        if filteredSessions.isEmpty {
                            Text("No chats found")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            ForEach(filteredSessions) { s in
                                HStack {
                                    Label {
                                        VStack(alignment: .leading, spacing: 2) {
                                            let firstMsg = s.messages.first(where: { $0.role == .user })?.content.compactMap { content -> String? in
                                                if case .text(let t) = content { return t }
                                                return nil
                                            }.first ?? "New Conversation"

                                            Text(firstMsg)
                                                .font(.body)
                                                .lineLimit(1)

                                            Text(s.mode.rawValue)
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(s.mode == .agent ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                                                .foregroundStyle(s.mode == .agent ? Color.purple : Color.blue)
                                                .cornerRadius(3)
                                        }
                                    } icon: {
                                        Image(systemName: s.mode == .agent ? "sparkles" : "bubble.left.and.bubble.right")
                                            .foregroundStyle(viewModel.session.id == s.id ? .accentColor : .secondary)
                                    }

                                    Spacer()

                                    // Delete Button on Hover or Context Menu
                                    Button {
                                        withAnimation(.spring()) {
                                            viewModel.deleteSession(s)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .tag(s.id)
                                .padding(.vertical, 4)
                                .contextMenu {
                                    Button("Delete Chat", role: .destructive) {
                                        viewModel.deleteSession(s)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 300)
                .background(Color(NSColor.windowBackgroundColor))
            }

            // Column 2: Center Conversation (Main Chat Panel)
            VStack(spacing: 0) {
                // Mode Segmented Picker and Controls
                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring()) {
                            showSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .foregroundColor(showSidebar ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Chat Sidebar")

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

                // Input Bar (Attachments picker + textfield + Send)
                AgentInputBarView(viewModel: viewModel)
            }
            .frame(minWidth: 400)
            .layoutPriority(1) // High layout priority ensures Center is highest priority and takes majority space!

            // Column 3: Right "Plan & Tasks" Checklist Inspector
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
        .macDesktopOptimized()
    }
}
