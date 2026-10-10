import SwiftUI

/// Plain inline view visualizing autonomous execution progress of the Assist Planner.
public struct AssistPlannerView: View {
    @ObservedObject var planner = TasksAIPlanner.shared

    public init() {}

    public var body: some View {
        if planner.isPlanning {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
                    .tint(.accentColor)
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Formulating execution plan")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } else if let plan = planner.currentPlan {
            VStack(alignment: .leading, spacing: 8) {
                planHeader(plan)
                stepsList(plan)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private func planHeader(_ plan: AssistExecutionPlan) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.clipboard")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 11))

            Text(plan.goal)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            statusBadge(plan.status)
        }
    }

    private func stepsList(_ plan: AssistExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plan.steps) { step in
                HStack(alignment: .top, spacing: 6) {
                    statusIcon(step.status)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.description)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(step.status == .pending ? Color.secondary : Color.primary)
                        if let error = step.result?.error {
                            Text(error)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(_ status: AssistExecutionStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 10))
            case .running:
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 10, height: 10)
                    .tint(.accentColor)
            case .completed:
                Image(systemName: "checkmark")
                    .foregroundStyle(.green)
                    .font(.system(size: 9, weight: .bold))
            case .failed:
                Image(systemName: "xmark")
                    .foregroundStyle(.red)
                    .font(.system(size: 9, weight: .bold))
            case .skipped:
                Image(systemName: "slash.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 9))
            }
        }
        .frame(width: 12, height: 12)
    }

    private func statusBadge(_ status: AssistExecutionStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: AssistExecutionStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .accentColor
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}
