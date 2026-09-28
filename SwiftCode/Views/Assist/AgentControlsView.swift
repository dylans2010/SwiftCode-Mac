import SwiftUI

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

                if status == .failed || status == .stalled {
                    Button {
                        agentSession.retryLastStep()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Step")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help("Retry the last step")
                }

                Spacer()

                // Continuous Takeover Toggle Button
                let isTakeover = UserDefaults.standard.bool(forKey: "assist.takeoverEnabled")
                Button {
                    let next = !isTakeover
                    UserDefaults.standard.set(next, forKey: "assist.takeoverEnabled")
                    agentSession.state.takeoverActive = next
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isTakeover ? "infinity.circle.fill" : "infinity.circle")
                            .foregroundStyle(isTakeover ? .green : .secondary)
                        Text(isTakeover ? "Takeover Active" : "Takeover Off")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(isTakeover ? .green : .secondary)
                .help(isTakeover ? "Continuous takeover is active. Click to stop expanding into new goals after this task." : "Enable continuous autonomous multi-goal expansion.")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            EmptyView()
        }
    }
}
