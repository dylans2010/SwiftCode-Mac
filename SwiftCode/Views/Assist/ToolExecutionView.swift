import SwiftUI

/// Plain inline row displaying active tool execution or in-flight model runtime status
/// with an SF Symbol and status color outside the chat bubble.
@MainActor
public struct ToolExecutionView: View {
    @ObservedObject private var manager: AssistManager

    public init(manager: AssistManager = .shared) {
        self.manager = manager
    }

    public init(agentSession: AssistAgentSession) {
        self.manager = .shared
    }

    public var body: some View {
        if let activeInfo = currentActiveOperation {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
                    .tint(activeInfo.color)

                Image(systemName: activeInfo.symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(activeInfo.color)

                Text(activeInfo.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .transition(.opacity)
        } else {
            EmptyView()
        }
    }

    private struct ActiveOperationInfo {
        let symbol: String
        let color: Color
        let description: String
    }

    private var currentActiveOperation: ActiveOperationInfo? {
        let isBusy = manager.isProcessing ||
                     CodexBridgeManager.shared.streamStatus == "Streaming" ||
                     manager.agentSession.state.status == .executingTool ||
                     manager.agentSession.state.status == .inspectingResult ||
                     manager.agentSession.state.status == .executing

        guard isBusy else { return nil }

        // 1. Check if a tool/worker in the active message's activityGroup is actively running
        if let lastMessage = manager.messages.last,
           let activity = lastMessage.activityGroup,
           activity.isExecuting {
            if let runningTool = activity.tools.first(where: { $0.status == .running || $0.status == .retrying }) {
                let symbol = toolSymbol(for: runningTool.toolId, summary: runningTool.purpose)
                let desc = runningTool.displayLabel ?? (!runningTool.purpose.isEmpty ? runningTool.purpose : runningTool.toolId)
                return ActiveOperationInfo(symbol: symbol, color: .accentColor, description: desc)
            }
            if let runningWorker = activity.workers.first(where: { $0.status == .running }) {
                return ActiveOperationInfo(symbol: "person.2", color: .accentColor, description: runningWorker.userFacingTitle)
            }
            if let runningBuild = activity.builds.first(where: { $0.status == .running }) {
                // Describe the actual build (scheme) instead of a canned label.
                let scheme = runningBuild.scheme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return ActiveOperationInfo(symbol: "hammer", color: .accentColor, description: scheme.isEmpty ? "xcodebuild" : "xcodebuild -scheme \(scheme)")
            }
            if let runningTerm = activity.terminalCommands.first(where: { $0.status == .running }) {
                return ActiveOperationInfo(symbol: "terminal", color: .accentColor, description: runningTerm.command)
            }
        }

        // 2. Check agentSession events/status
        let sessionStatus = manager.agentSession.state.status
        if sessionStatus == .executingTool || sessionStatus == .inspectingResult || sessionStatus == .executing {
            if let lastEvent = manager.agentSession.state.events.last(where: { $0.state == .executingTool || $0.state == .inspectingResult || $0.state == .executing }),
               !lastEvent.summary.isEmpty {
                return ActiveOperationInfo(
                    symbol: toolSymbol(for: lastEvent.summary, summary: ""),
                    color: .accentColor,
                    description: lastEvent.summary
                )
            }
        }

        // 3. Check manager.currentActivityStatus
        let statusText = manager.currentActivityStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statusText.isEmpty && statusText.lowercased() != "idle" && statusText.lowercased() != "cancelled" {
            let symbol = toolSymbol(for: statusText, summary: "")
            return ActiveOperationInfo(symbol: symbol, color: .accentColor, description: statusText)
        }

        // 4. Codex bridge tool
        let codexTool = CodexBridgeManager.shared.activeToolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !codexTool.isEmpty {
            return ActiveOperationInfo(symbol: toolSymbol(for: codexTool, summary: ""), color: .accentColor, description: codexTool)
        }

        // 5. Nothing concrete is known: show no fabricated status.
        return nil
    }

    private func toolSymbol(for idOrTitle: String, summary: String) -> String {
        let text = "\(idOrTitle) \(summary)".lowercased()
        if text.contains("read") || text.contains("view") || text.contains("cat") { return "doc.text" }
        if text.contains("write") || text.contains("edit") || text.contains("replace") || text.contains("patch") || text.contains("modify") { return "pencil" }
        if text.contains("build") || text.contains("compile") || text.contains("xcodebuild") { return "hammer" }
        if text.contains("test") { return "play" }
        if text.contains("term") || text.contains("run") || text.contains("command") || text.contains("bash") || text.contains("exec") || text.contains("shell") { return "terminal" }
        if text.contains("search") || text.contains("grep") || text.contains("find") { return "magnifyingglass" }
        if text.contains("git") || text.contains("branch") || text.contains("commit") { return "arrow.triangle.branch" }
        if text.contains("review") { return "checkmark.shield" }
        if text.contains("worker") || text.contains("subagent") { return "person.2" }
        if text.contains("mcp") || text.contains("server") { return "network.badge.shield.half.filled" }
        if text.contains("composio") { return "link.badge.plus" }
        if text.contains("model") || text.contains("response") || text.contains("generating") || text.contains("preparing") || text.contains("connecting") { return "sparkles" }
        return "wrench.and.screwdriver"
    }
}
