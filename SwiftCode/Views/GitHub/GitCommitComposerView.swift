import SwiftUI

@MainActor
struct GitCommitComposerView: View {
    @Binding var message: String
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Commit Composer", systemImage: "pencil.and.outline")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.bottom, 16)

            // Scrollable content
            ScrollView {
                VStack(spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Commit Message")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            TextEditor(text: $message)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 120, maxHeight: 200)
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
        }
        .sourceControlEmbedded()
    }
}
