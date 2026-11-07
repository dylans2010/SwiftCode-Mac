import SwiftUI

struct CodexUndoRedoView: View {
    @StateObject private var workspace = CodexWorkspaceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Undo / Redo", systemImage: "arrow.uturn.backward.circle")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                actionButton(title: "Undo Prompt", systemImage: "arrow.uturn.backward", tint: [.orange, .pink], enabled: !workspace.promptUndoStack.isEmpty) { workspace.undoPrompt() }
                actionButton(title: "Redo Prompt", systemImage: "arrow.uturn.forward", tint: [.blue, .cyan], enabled: !workspace.promptRedoStack.isEmpty) { workspace.redoPrompt() }
                actionButton(title: "Undo Output", systemImage: "doc.badge.arrow.up", tint: [.purple, .indigo], enabled: !workspace.codeUndoStack.isEmpty) { workspace.undoCode() }
                actionButton(title: "Redo Output", systemImage: "doc.badge.arrow.down", tint: [.green, .mint], enabled: !workspace.codeRedoStack.isEmpty) { workspace.redoCode() }
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionButton(title: String, systemImage: String, tint: [Color], enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: enabled ? tint : [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(enabled ? 0.18 : 0.08), lineWidth: 1)
                )
                .shadow(color: (enabled ? tint.first! : .clear).opacity(0.24), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .scaleEffect(enabled ? 1 : 0.99)
        .opacity(enabled ? 1 : 0.58)
        .animation(.spring(response: 0.22, dampingFraction: 0.76), value: enabled)
        .disabled(!enabled)
    }
}
