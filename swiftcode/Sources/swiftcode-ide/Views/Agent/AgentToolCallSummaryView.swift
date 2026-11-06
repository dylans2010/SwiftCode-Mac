// AgentToolCallSummaryView.swift
//
// Ported from Legacy `SwiftCode/Views/Agent/AgentToolCallSummaryView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: dedicated Calling <tool> row with arguments
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI

struct AgentToolCallSummaryView: View {
    let name: String
    let arguments: String

    var body: some View {
        HStack {
            Image(systemName: "terminal")
            Text("Calling \(name)...")
                .font(.subheadline)
            Spacer()
        }
        .padding(8)
        .liquidGlass(style: .subtle, cornerRadius: 6)
    }
}
