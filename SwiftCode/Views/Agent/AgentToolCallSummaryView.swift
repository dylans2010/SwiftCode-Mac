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
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(6)
    }
}
