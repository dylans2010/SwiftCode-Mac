import SwiftUI

struct AISuggestionActionBar: View {
    let onAction: (AIAction) -> Void

    var body: some View {
        HStack {
            Button("Insert") { onAction(.insert) }
            Button("Replace") { onAction(.replace) }
            Button("Apply") { onAction(.apply) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
    }
}
