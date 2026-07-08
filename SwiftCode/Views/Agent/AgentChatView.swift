import SwiftUI

public struct AgentChatView: View {
    @Environment(AgentViewModel.self) var viewModel
    @State private var showChecklist = true

    public init() {}

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                AgentMessageListView(messages: viewModel.session.messages, viewModel: viewModel)

                Divider()

                AgentInputBarView(viewModel: viewModel)
            }
            .frame(minWidth: 300)

            if showChecklist {
                VStack(spacing: 0) {
                    Text("Plan & Tasks")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    AgentChecklistView(state: viewModel.session.checklist)
                }
                .frame(width: 250)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showChecklist.toggle() }) {
                    Label("Checklist", systemImage: "checklist")
                }
            }
        }
        .macDesktopOptimized()
    }
}
