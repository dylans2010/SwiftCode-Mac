import SwiftUI

public struct AssistPlanView: View {
    let plan: AssistPlan
    @StateObject private var assistManager = AssistManager.shared
    @State private var showingDiff = false

    public init(plan: AssistPlan) {
        self.plan = plan
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(.orange)
                Text(plan.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(plan.status.rawValue.capitalized)
                    .font(.caption.bold())
                    .foregroundStyle(plan.status == .pending ? .yellow : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.steps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                        Text(step.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Preview") {
                    showingDiff = true
                }
                .buttonStyle(.bordered)
                .tint(.blue)

                Spacer()

                Button("Reject") {
                    assistManager.rejectPlan()
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button("Apply") {
                    Task {
                        try? await assistManager.applyPlan(plan)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.orange.opacity(0.2)),
            alignment: .top
        )
        .sheet(isPresented: $showingDiff) {
            AssistDiffView(plan: plan)
        }
    }
}
