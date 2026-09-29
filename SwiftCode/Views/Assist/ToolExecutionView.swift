import SwiftUI

@MainActor
public struct ToolExecutionView: View {
    let agentSession: AssistAgentSession

    public init(agentSession: AssistAgentSession) {
        self.agentSession = agentSession
    }

    public var body: some View {
        let status = agentSession.state.status
        if status == .executingTool || status == .inspectingResult {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.4)
                            .tint(.secondary)
                        Text("Executing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if let lastEvent = agentSession.state.events.last(where: { $0.state == .executingTool || $0.state == .inspectingResult }) {
                        Text(lastEvent.summary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Awaiting tool execution...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
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
