import SwiftUI

struct AISuggestionActionBar: View {
    let onAction: (AIAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Insert") { onAction(.insert) }
            Button("Replace") { onAction(.replace) }
            Button("Apply") { onAction(.apply) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlass(style: .floatingBar, cornerRadius: 8)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
