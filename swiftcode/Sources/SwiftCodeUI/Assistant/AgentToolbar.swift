// Ported from Legacy `SwiftCode/Views/AI/AI New/AgentToolbar.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> thinMaterial (see Adaptive notes).
// Self-contained Agent/Chat tab switcher; the host owns the selectedTab binding.
// Wiring: AssistantPane (swiftcode-ide) — add as the tab switcher above the
// assistant column; no Agent/Chat tabs exist there yet.

import SwiftUI

struct AgentToolbar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 20) {
            Button(action: { selectedTab = 0 }) {
                VStack {
                    Image(systemName: "bolt.fill")
                    Text("Agent")
                        .font(.caption)
                }
                .foregroundColor(selectedTab == 0 ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: { selectedTab = 1 }) {
                VStack {
                    Image(systemName: "message.fill")
                    Text("Chat")
                        .font(.caption)
                }
                .foregroundColor(selectedTab == 1 ? .blue : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
