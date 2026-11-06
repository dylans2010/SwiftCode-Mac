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
