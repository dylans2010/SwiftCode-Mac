import SwiftUI

/// Plain inline row displaying active tool execution with an SF Symbol and status color.
@MainActor
public struct ToolExecutionView: View {
    let agentSession: AssistAgentSession

    public init(agentSession: AssistAgentSession) {
        self.agentSession = agentSession
    }

    public var body: some View {
        let status = agentSession.state.status
        if status == .executingTool || status == .inspectingResult {
            if let lastEvent = agentSession.state.events.last(where: { $0.state == .executingTool || $0.state == .inspectingResult }),
               !lastEvent.summary.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                        .tint(.accentColor)

                    Image(systemName: toolSymbol(for: lastEvent.summary))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)

                    Text(lastEvent.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }

    private func toolSymbol(for summary: String) -> String {
        let lower = summary.lowercased()
        if lower.contains("read") || lower.contains("view") { return "doc.text" }
        if lower.contains("write") || lower.contains("edit") || lower.contains("replace") || lower.contains("patch") { return "pencil" }
        if lower.contains("build") || lower.contains("compile") { return "hammer" }
        if lower.contains("test") { return "play" }
        if lower.contains("term") || lower.contains("run") || lower.contains("command") { return "terminal" }
        if lower.contains("search") || lower.contains("grep") || lower.contains("find") { return "magnifyingglass" }
        if lower.contains("review") { return "checkmark.shield" }
        return "wrench.and.screwdriver"
    }
}
