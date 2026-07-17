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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            EmptyView()
        }
    }
}
