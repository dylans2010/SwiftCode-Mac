// AgentChecklistView.swift
//
// Ported from Legacy `SwiftCode/Views/Agent/AgentChecklistView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: checklist UI with per-step status icons
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): AgentChecklistState, AgentChecklistTaskStatus.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI

struct AgentChecklistView: View {
    let state: AgentChecklistState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plan")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(style: .subtle, cornerRadius: 8)
                .padding([.horizontal, .top])

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
