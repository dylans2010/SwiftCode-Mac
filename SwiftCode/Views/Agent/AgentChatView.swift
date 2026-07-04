import SwiftUI

public struct AgentChatView: View {
    @StateObject var viewModel = AgentViewModel()
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
                AgentChecklistView(state: viewModel.session.checklist)
                    .frame(width: 250)
            }
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showChecklist.toggle() }) {
                    Label("Checklist", systemImage: "checklist")
                }
            }
        }
    }
}
