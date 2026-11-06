// AgentModeView.swift
//
// Ported from Legacy `SwiftCode/Views/AI/AI New/AgentModeView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: structured Tools Executed list from AIToolExecutionView
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): CodeChangesView.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI

struct AgentModeView: View {
    var body: some View {
        VStack(spacing: 20) {
            AIToolExecutionView()
            CodeChangesView()
            Spacer()
        }
        .padding()
        .liquidGlass(style: .standard, cornerRadius: 16)
    }
}
