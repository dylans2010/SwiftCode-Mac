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
                    HStack {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .foregroundStyle(.orange)
                        Text("Progress Timeline")
                            .font(.subheadline.bold())
                        Spacer()
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 10) {
                                timelineIcon(for: event.state)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.summary)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(event.timestamp, style: .time)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(4)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
        }
    }

    private func timelineIcon(for state: AgentSessionStatus) -> some View {
        Group {
            switch state {
            case .idle:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            case .planning:
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
            case .selectingTool:
                Image(systemName: "hand.tap.fill")
                    .foregroundStyle(.blue)
            case .executingTool:
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.orange)
            case .inspectingResult:
                Image(systemName: "eye.fill")
                    .foregroundStyle(.cyan)
            case .validating:
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "nosign")
                    .foregroundStyle(.gray)
            case .stalled:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
        .frame(width: 14, height: 14)
    }
}
