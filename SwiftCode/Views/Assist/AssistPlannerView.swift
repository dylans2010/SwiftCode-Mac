import SwiftUI

/// A specialized view for visualizing the autonomous execution progress of the Assist Planner.
public struct AssistPlannerView: View {
    @ObservedObject var planner = TasksAIPlanner.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if planner.isPlanning {
                planningHeader
            } else if let plan = planner.currentPlan {
                planHeader(plan)
                stepsList(plan)
            } else {
                EmptyView()
            }
        }
        .padding()
        .background(Color(white: 0.12))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var planningHeader: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.orange)
            Text("Reasoning and Planning...")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
        }
    }

    private func planHeader(_ plan: AssistExecutionPlan) -> some View {
        HStack {
            Image(systemName: "cpu")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Autonomous Strategy")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(plan.goal)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            Spacer()
            statusBadge(plan.status)
        }
    }

    private func stepsList(_ plan: AssistExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(plan.steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    statusIcon(step.status)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.description)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(step.status == .pending ? Color.secondary : Color.white)
                        if let error = step.result?.error {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private func statusIcon(_ status: AssistExecutionStatus) -> some View {
        ZStack {
            switch status {
            case .pending:
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    .frame(width: 14, height: 14)
            case .running:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 14))
            case .skipped:
                Image(systemName: "slash.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
        }
    }

    private func statusBadge(_ status: AssistExecutionStatus) -> some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.2))
            .foregroundStyle(statusColor(status))
            .cornerRadius(4)
    }

    private func statusColor(_ status: AssistExecutionStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .orange
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}
