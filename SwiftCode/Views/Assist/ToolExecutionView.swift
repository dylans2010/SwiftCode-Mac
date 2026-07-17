import SwiftUI

@MainActor
public struct ToolExecutionView: View {
    let agentSession: AgentSession

    public init(agentSession: AgentSession) {
        self.agentSession = agentSession
    }

    public var body: some View {
        let status = agentSession.state.status
        if status == .executingTool || status == .inspectingResult {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(.orange)
                        Text("Active Tool execution")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                        Spacer()
                    }

                    if let lastEvent = agentSession.state.events.last(where: { $0.state == .executingTool || $0.state == .inspectingResult }) {
                        Text(lastEvent.summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Awaiting tool execution...")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
        } else {
            EmptyView()
        }
    }
}
