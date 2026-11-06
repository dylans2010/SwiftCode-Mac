import SwiftUI

struct AICoreView: View {
    @AppStorage("useCodexAsAgent") private var useCodexAsAgent = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            AssistantTheme.canvas
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    topHero

                    if useCodexAsAgent {
                        CodexMainView()
                    } else {
                        TraditionalAgentView(selectedTab: $selectedTab)
                    }
                }
                .padding()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: useCodexAsAgent)
    }

    private var topHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                AssistantSectionHeader(
                    eyebrow: useCodexAsAgent ? "Codex enabled" : "AI assistant",
                    title: useCodexAsAgent ? "Codex execution workspace" : "Modern AI workspace",
                    subtitle: useCodexAsAgent ? "Plan, generate, review diffs, and manage execution from one secure interface." : "Responsive chat, agent actions, and context-aware output in a rebuilt interface."
                )
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 10) {
                    Label(useCodexAsAgent ? "Codex" : "Assistant", systemImage: useCodexAsAgent ? "cpu.fill" : "message.badge.waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())

                    Toggle(isOn: $useCodexAsAgent) {
                        Text("Use Codex")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            Text(useCodexAsAgent ? "API credentials remain hidden, while all generation surfaces now share updated glassmorphism styling and clearer feedback." : "Switch between agent automation and conversational chat with consistent layouts, better readability, and polished interactions.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(20)
        .assistantGlassCard()
    }
}

struct TraditionalAgentView: View {
    @Binding var selectedTab: Int

    var body: some View {
        VStack(spacing: 18) {
            AgentToolbar(selectedTab: $selectedTab)

            Group {
                if selectedTab == 0 {
                    AgentModeView()
                } else {
                    ChatAIInterfaceView()
                }
            }
        }
    }
}
