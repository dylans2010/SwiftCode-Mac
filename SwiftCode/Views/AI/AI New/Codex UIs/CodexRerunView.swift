import SwiftUI

struct CodexRerunView: View {
    @StateObject private var workspace = CodexWorkspaceStore.shared
    let rerun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Rerun", systemImage: "arrow.clockwise.circle")
                    .font(.headline)
                Spacer()
                Button(action: rerun) {
                    Label("Rerun Prompt", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(workspace.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !workspace.previousOutput.isEmpty {
                Text("Previous output is preserved below for side-by-side review against the latest generation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Run the same prompt again without clearing the previous result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
