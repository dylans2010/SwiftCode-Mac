import SwiftUI

struct GitCommitComposerView: View {
    @Binding var message: String
    let onCommit: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Commit Composer", systemImage: "pencil.and.outline")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Spacer()
                }

                Text("Commit Message")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $message)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 180)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Button(action: onCommit) {
                    Text("Commit to Local Branch")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}
