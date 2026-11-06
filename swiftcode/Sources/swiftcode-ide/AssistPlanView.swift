// STAGED PORT — SwiftCode-Legacy `SwiftCode/Views/Assist/AssistPlanView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: swiftcode-ide (`swiftcode/Sources/swiftcode-ide/AssistPlanView.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - plan preview UI with Apply/Reject
// ADAPTATIONS:
//   - Observation adaptation (wiring-views): @ObservedObject/@StateObject over
//     @Observable models replaced with @State (@Bindable where `$` bindings are used).
//   - Added `import SwiftCodeAssistant` (views consume Assist models; module is a swiftcode-ide dependency).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AssistManager — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistManager.swift`)
// WIRING / REGISTRATION: Wire into the swiftcode-ide assistant UI (AssistantPane / AssistMainView) once the models it observes land. Remaining in-file work: @Observable adaptation (see ADAPTATIONS).

import SwiftUI
import SwiftCodeAssistant

public struct AssistPlanView: View {
    let plan: AssistPlan
    @State private var assistManager = AssistManager.shared
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
        .liquidGlass(style: .standard, cornerRadius: 12, tint: .orange)
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
