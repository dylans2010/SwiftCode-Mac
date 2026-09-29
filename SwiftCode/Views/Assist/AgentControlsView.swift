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
        } else {
            EmptyView()
        }
    }
}
