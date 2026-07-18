import SwiftUI

@MainActor
public struct TaskProgressView: View {
    let agentSession: AssistAgentSession

    public init(agentSession: AssistAgentSession) {
        self.agentSession = agentSession
    }

    public var body: some View {
        let plan = agentSession.state.plan
        if plan.isEmpty {
            EmptyView()
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "list.bullet.clipboard")
                            .foregroundStyle(.orange)
                        Text("Task Objectives")
                            .font(.subheadline.bold())
                        Spacer()
                        statusBadge(agentSession.state.status)
                    }

                    Text("Goal: \(agentSession.state.objective)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan) { step in
                            HStack(alignment: .top, spacing: 8) {
                                stepIcon(for: step)
                                Text(step.description)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(stepStyle(for: step))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
        }
    }

    private func stepIcon(for step: PlanStep) -> some View {
        // Find if this step is completed (is it in completedActions?)
        let isCompleted = agentSession.state.completedActions.contains(step.description)
        return Group {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if agentSession.state.status == .executingTool && agentSession.state.events.last?.summary.contains(step.toolId) == true {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .frame(width: 12, height: 12)
    }

    private func stepStyle(for step: PlanStep) -> Color {
        let isCompleted = agentSession.state.completedActions.contains(step.description)
        return isCompleted ? .secondary : .primary
    }

    private func statusBadge(_ status: AgentSessionStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor(status).opacity(0.12))
            .foregroundStyle(badgeColor(status))
            .cornerRadius(4)
    }

    private func badgeColor(_ status: AgentSessionStatus) -> Color {
        switch status {
        case .idle, .cancelled, .terminated:
            return .gray
        case .planning, .planningReview, .selectingTools, .executingTools, .selectingTool, .executingTool, .inspectingResult, .executingStrategy, .updatingRepository, .gatheringContext, .collectingContext, .analyzingRepository, .receivingRequest, .generatingSummary:
            return .orange
        case .validating, .reviewing, .initializing:
            return .purple
        case .finished, .completed:
            return .green
        case .failed, .reviewFailed, .recovering, .stalled:
            return .red
        case .awaitingApproval, .waitingForUserApproval:
            return .blue
        }
    }
}
