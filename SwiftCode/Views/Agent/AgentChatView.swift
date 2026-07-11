import SwiftUI

public struct AgentChatView: View {
    @Environment(AgentViewModel.self) var viewModel
    @State private var showChecklist = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Local Header Bar inside the docked panel
            HStack {
                Button(action: {
                    withAnimation {
                        showChecklist.toggle()
                    }
                }) {
                    Label(showChecklist ? "Hide Plan" : "Show Plan", systemImage: "checklist")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    AgentMessageListView(messages: viewModel.session.messages, viewModel: viewModel)

                    Divider()

                    AgentInputBarView(viewModel: viewModel)
                }
                .frame(minWidth: 200)

                if showChecklist {
                    VStack(spacing: 0) {
                        Text("Plan & Tasks")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        AgentChecklistView(state: viewModel.session.checklist)
                    }
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 350)
                    .background(Color(NSColor.controlBackgroundColor))
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .macDesktopOptimized()
    }
}
