import SwiftUI

public struct AgentChatView: View {
    @Environment(AgentViewModel.self) var viewModel
    @State private var showChecklist = true

    public init() {}

    public var body: some View {
        @Bindable var viewModel = viewModel

        HSplitView {
            // Left/Center Area: Chat & Message flow
            VStack(spacing: 0) {
                // Professional Header with Segmented Mode Picker & Conversation Actions
                HStack(spacing: 12) {
                    Picker("Mode", selection: $viewModel.mode) {
                        ForEach(AIAssistantMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                    .help("Switch between read-only 'Chat' and interactive 'Agent' modes")

                    Spacer()

                    // Quick Clear Conversation Button
                    Button(action: clearConversation) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Clear Chat Conversation")
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Adaptive Message List View
                AgentMessageListView(messages: viewModel.session.messages, viewModel: viewModel)
                    .frame(maxWidth: .infinity)

                Divider()

                // Desktop Optimized Message Input Bar
                AgentInputBarView(viewModel: viewModel)
            }
            .frame(minWidth: 320, idealWidth: 600, maxWidth: .infinity)
            .layoutPriority(2) // Gives the center conversation view highest priority for space reallocation

            // Right Area: Plan & Tasks Checklist Inspector (Agent Mode Only, or toggleable)
            if showChecklist {
                VStack(spacing: 0) {
                    HStack {
                        Label("Plan & Tasks", systemImage: "checklist")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    AgentChecklistView(state: viewModel.session.checklist)
                }
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)
                .background(Color(NSColor.controlBackgroundColor))
                .layoutPriority(1) // Lower priority keeps inspector compact and prevents excessive expanding
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .opacity
                ))
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChecklist.toggle()
                    }
                }) {
                    Label("Checklist", systemImage: "checklist")
                        .foregroundColor(showChecklist ? .accentColor : .primary)
                }
                .help("Toggle Checklist Panel")
            }
        }
        .macDesktopOptimized()
    }

    private func clearConversation() {
        withAnimation {
            viewModel.session.messages.removeAll()
            viewModel.session.checklist = AgentChecklistState(tasks: [])
            viewModel.session.turnState = .idle
        }
    }
}
