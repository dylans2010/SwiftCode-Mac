import SwiftUI

struct AgentChecklistView: View {
    let state: AgentChecklistState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plan")
                .font(.headline)
                .padding()

            List(state.tasks) { task in
                HStack(alignment: .top) {
                    statusIcon(task.status)

                    VStack(alignment: .leading) {
                        Text(task.title)
                            .font(.subheadline)
                            .strikethrough(task.status == .completed)

                        if let detail = task.detail {
                            Text(detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: AgentChecklistTaskStatus) -> some View {
        switch status {
        case .queued:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        case .inProgress:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}
