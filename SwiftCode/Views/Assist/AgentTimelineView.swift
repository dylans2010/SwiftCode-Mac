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
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Progress Timeline")
                                .font(.subheadline.bold())
                            Text("Real-time execution checkpoints and agent logs")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Small pulsing status indicator for active runs
                        if agentSession.state.status != .terminated && agentSession.state.status != .failed && agentSession.state.status != .finished && agentSession.state.status != .completed {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 6, height: 6)
                                Text("ACTIVE RUN")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                            HStack(alignment: .top, spacing: 14) {
                                // Left Track Column: Dot & Vertical line
                                VStack(spacing: 0) {
                                    ZStack {
                                        Circle()
                                            .fill(timelineColor(for: event.state).opacity(0.12))
                                            .frame(width: 24, height: 24)

                                        timelineIcon(for: event.state)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(timelineColor(for: event.state))
                                    }

                                    // Connecting line to the next dot
                                    if index < events.count - 1 {
                                        Rectangle()
                                            .fill(LinearGradient(
                                                gradient: Gradient(colors: [timelineColor(for: event.state).opacity(0.5), timelineColor(for: events[index + 1].state).opacity(0.5)]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ))
                                            .frame(width: 2, height: 28)
                                    }
                                }

                                // Right Content Card Column
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(event.summary)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineSpacing(2)

                                        Spacer()

                                        Text(event.timestamp, style: .time)
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                    }

                                    // Optional Status Badge
                                    Text(event.state.rawValue.uppercased())
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(timelineColor(for: event.state))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(timelineColor(for: event.state).opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                                }
                                .padding(.vertical, 2)
                            }
                            .padding(.bottom, index < events.count - 1 ? 8 : 0)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .padding(12)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding(.horizontal, 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: events.count)
        }
    }

    private func timelineColor(for state: AgentSessionStatus) -> Color {
        switch state {
        case .idle:
            return .secondary
        case .receivingRequest, .understandingRequest:
            return .blue
        case .analyzingRepository, .inspectingResult:
            return .cyan
        case .collectingContext, .gatheringContext:
            return .yellow
        case .planningReview, .planning:
            return .purple
        case .awaitingApproval, .waitingForUserApproval:
            return .red
        case .executingStrategy, .executingTool, .executingTools:
            return .orange
        case .selectingTools, .selectingTool:
            return .blue
        case .reviewFailed:
            return .red
        case .recovering:
            return .orange
        case .generatingSummary:
            return .indigo
        case .terminated, .failed:
            return .red
        case .cancelled:
            return .secondary
        case .stalled:
            return .yellow
        case .completed, .finished:
            return .green
        default:
            return .blue
        }
    }

    private func timelineIcon(for state: AgentSessionStatus) -> Image {
        switch state {
        case .idle:
            return Image(systemName: "circle")
        case .receivingRequest:
            return Image(systemName: "bubble.left.and.bubble.right.fill")
        case .analyzingRepository:
            return Image(systemName: "magnifyingglass")
        case .collectingContext:
            return Image(systemName: "folder.fill")
        case .planningReview:
            return Image(systemName: "doc.text.magnifyingglass")
        case .awaitingApproval:
            return Image(systemName: "lock.shield.fill")
        case .executingStrategy:
            return Image(systemName: "play.fill")
        case .selectingTools:
            return Image(systemName: "hand.tap.fill")
        case .executingTools:
            return Image(systemName: "gearshape.fill")
        case .reviewFailed:
            return Image(systemName: "exclamationmark.octagon.fill")
        case .recovering:
            return Image(systemName: "arrow.counterclockwise.shield.fill")
        case .generatingSummary:
            return Image(systemName: "doc.richtext.fill")
        case .terminated:
            return Image(systemName: "xmark.octagon.fill")
        case .initializing:
            return Image(systemName: "arrow.triangle.2.circlepath")
        case .understandingRequest:
            return Image(systemName: "questionmark.circle")
        case .gatheringContext:
            return Image(systemName: "folder.fill")
        case .planning:
            return Image(systemName: "brain.head.profile")
        case .selectingTool:
            return Image(systemName: "hand.tap.fill")
        case .executingTool:
            return Image(systemName: "gearshape.fill")
        case .waitingForUserApproval:
            return Image(systemName: "lock.shield.fill")
        case .updatingRepository:
            return Image(systemName: "doc.badge.gearshape.fill")
        case .inspectingResult:
            return Image(systemName: "eye.fill")
        case .validating:
            return Image(systemName: "checkmark.shield.fill")
        case .reviewing:
            return Image(systemName: "eye.circle")
        case .completing:
            return Image(systemName: "ellipsis.circle")
        case .finished, .completed:
            return Image(systemName: "checkmark.circle.fill")
        case .failed:
            return Image(systemName: "xmark.circle.fill")
        case .cancelled:
            return Image(systemName: "nosign")
        case .stalled:
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }
}
