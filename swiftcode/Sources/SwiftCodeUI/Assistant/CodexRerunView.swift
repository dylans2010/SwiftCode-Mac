// Ported from Legacy `SwiftCode/Views/AI/AI New/Codex UIs/CodexRerunView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim. BLOCKED reference: CodexWorkspaceStore (Legacy
// `Views/AI/AI New/Codex UIs/CodexMainView.swift`, PARTIAL, another scope) —
// the view reads .shared.prompt/.previousOutput. The `rerun` closure is host-owned.
// Wiring: the Codex assistant pane, next to the prompt input.

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
