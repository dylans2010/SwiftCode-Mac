import SwiftUI

@MainActor
public struct AgentTimelineView: View {
    let agentSession: AssistAgentSession

    public init(agentSession: AssistAgentSession) {
        self.agentSession = agentSession
    }

    public var body: some View {
        let events = agentSession.state.events
        if events.isEmpty {
            EmptyView()
        } else {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Text("Progress")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)

                        if isExecuting {
                            ProgressView()
                                .scaleEffect(0.35)
                                .tint(.secondary)
                        }

                        Spacer()
                    }

                    Divider()

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(timelineColor(for: event.state))
                                        .frame(width: 5, height: 5)

                                    if index < events.count - 1 {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.15))
                                            .frame(width: 1, height: 20)
                                    }
                                }
                                .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(event.summary)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Spacer()

                                        Text(event.timestamp, style: .time)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                            .padding(.bottom, index < events.count - 1 ? 4 : 0)
                        }
                    }
                }
                .padding(10)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
        }
    }

    private var isExecuting: Bool {
        let status = agentSession.state.status
        return status != .terminated && status != .failed && status != .finished && status != .completed
    }

    private func timelineColor(for state: AgentSessionStatus) -> Color {
        switch state {
        case .idle, .cancelled:
            return .secondary
        case .terminated, .failed, .reviewFailed:
            return .red
        case .completed, .finished:
            return .green
        case .stalled:
            return .orange
        default:
            return .accentColor
        }
    }
}
