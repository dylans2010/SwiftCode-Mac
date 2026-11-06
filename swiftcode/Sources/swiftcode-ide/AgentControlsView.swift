// STAGED PORT — SwiftCode-Legacy `SwiftCode/Views/Assist/AgentControlsView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: swiftcode-ide (`swiftcode/Sources/swiftcode-ide/AgentControlsView.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Retry last step action
//   - Takeover enable/active toggle UI
// ADAPTATIONS:
//   - Added `import SwiftCodeAssistant` (views consume Assist models; module is a swiftcode-ide dependency).
// UNRESOLVED DEPENDENCIES: none found by static scan (SwiftUI/Foundation/Apple-framework names excluded).
// WIRING / REGISTRATION: Wire into the swiftcode-ide assistant UI (AssistantPane / AssistMainView) once the models it observes land.

import SwiftUI
import SwiftCodeAssistant

@MainActor
public struct AgentControlsView: View {
    let agentSession: AssistAgentSession

    public init(agentSession: AssistAgentSession) {
        self.agentSession = agentSession
    }

    public var body: some View {
        let status = agentSession.state.status
        if status != .idle && status != .completed && status != .cancelled {
            HStack(spacing: 12) {
                Button {
                    agentSession.cancel()
                } label: {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop Agent")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Cancel the active autonomous agent session")

                if status == .failed {
                    Button {
                        agentSession.retryLastStep()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.bordered)
                    .help("Retry the last step")
                }

                Spacer()

                let isTakeover = UserDefaults.standard.bool(forKey: "assist.takeoverEnabled")
                Button {
                    let next = !isTakeover
                    UserDefaults.standard.set(next, forKey: "assist.takeoverEnabled")
                    agentSession.state.takeoverActive = next
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isTakeover ? "infinity.circle.fill" : "infinity.circle")
                            .foregroundStyle(isTakeover ? .green : .secondary)
                        Text(isTakeover ? "Takeover Active" : "Takeover Off")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .help(isTakeover ? "Continuous takeover is active. Click to stop expanding into new goals after this task." : "Enable continuous autonomous multi-goal expansion.")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .liquidGlass(style: .subtle, cornerRadius: 8)
        } else {
            EmptyView()
        }
    }
}
