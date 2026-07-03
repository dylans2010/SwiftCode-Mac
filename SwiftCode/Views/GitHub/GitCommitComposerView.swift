import SwiftUI

struct GitCommitComposerView: View {
    @Binding var message: String
    let onCommit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextEditor(text: $message)
                .frame(height: 80)
                .border(Color.secondary.opacity(0.2))
            Button("Commit", action: onCommit)
                .disabled(message.isEmpty)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
    }
}
