import SwiftUI
import AppKit

/// Redesigned plain inline activity view rendering real-time tool executions,
/// builds, tests, file modifications, and worker tasks without cards, boxes, or borders.
public struct AssistActivityView: View {
    public let activityGroup: AssistActivityGroup
    @State private var expandedOutputIds: Set<UUID> = []

    public init(activityGroup: AssistActivityGroup) {
        self.activityGroup = activityGroup
    }

    public var body: some View {
        if !activityGroup.hasContent {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // 1. Tool executions
                ForEach(activityGroup.tools) { tool in
                    toolRow(for: tool)
                }

                // 2. File modifications
                ForEach(activityGroup.files) { file in
                    fileRow(for: file)
                }

                // 3. Terminal commands
                ForEach(activityGroup.terminalCommands) { term in
                    terminalRow(for: term)
                }

                // 4. Builds
                ForEach(activityGroup.builds) { build in
                    buildRow(for: build)
                }

                // 5. Tests
                ForEach(activityGroup.tests) { test in
                    testRow(for: test)
                }

                // 6. Workers
                ForEach(activityGroup.workers) { worker in
                    workerRow(for: worker)
                }

                // 7. Recoveries
                ForEach(activityGroup.recoveries) { recovery in
                    recoveryRow(for: recovery)
                }

                // 8. Verifications
                ForEach(activityGroup.verifications) { verification in
                    verificationRow(for: verification)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Tool Row

    @ViewBuilder
    private func toolRow(for tool: ToolActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Status icon & tool symbol
                toolStatusIcon(for: tool)

                // Readable concise action description
                Text(toolActionDescription(for: tool))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(tool.status == .failed ? Color.red : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Duration or status detail
                if tool.duration > 0 {
                    Text(String(format: "%.1fs", tool.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            // Output/result display cleanly as plain secondary monospaced text underneath
            let outputText = displayOutput(for: tool)
            if !outputText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(outputText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(expandedOutputIds.contains(tool.id) ? nil : 3)
                        .textSelection(.enabled)

                    if outputText.components(separatedBy: .newlines).count > 3 || outputText.count > 180 {
                        Button {
                            if expandedOutputIds.contains(tool.id) {
                                expandedOutputIds.remove(tool.id)
                            } else {
                                expandedOutputIds.insert(tool.id)
                            }
                        } label: {
                            Text(expandedOutputIds.contains(tool.id) ? "Show less" : "Show output")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder
    private func toolStatusIcon(for tool: ToolActivityItem) -> some View {
        let symbol = toolSymbolName(for: tool)
        switch tool.status {
        case .running, .retrying:
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
                    .tint(.accentColor)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        case .completed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.green)
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .failed:
            HStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.red)
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red)
            }
        case .pending:
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .skipped, .cancelled:
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func toolSymbolName(for tool: ToolActivityItem) -> String {
        let id = tool.toolId.lowercased()
        if id.contains("read") || id.contains("view") || id.contains("cat") {
            return "doc.text"
        } else if id.contains("write") || id.contains("edit") || id.contains("replace") || id.contains("patch") || id.contains("modify") {
            return "pencil"
        } else if id.contains("build") || id.contains("compile") || id.contains("xcodebuild") {
            return "hammer"
        } else if id.contains("test") {
            return "play"
        } else if id.contains("term") || id.contains("command") || id.contains("bash") || id.contains("exec") || id.contains("shell") {
            return "terminal"
        } else if id.contains("search") || id.contains("grep") || id.contains("find") {
            return "magnifyingglass"
        } else if id.contains("git") || id.contains("branch") || id.contains("commit") {
            return "arrow.triangle.branch"
        } else if id.contains("dir") || id.contains("folder") || id.contains("ls") {
            return "folder"
        } else if id.contains("browser") || id.contains("web") || id.contains("url") {
            return "globe"
        } else if id.contains("review") {
            return "checkmark.shield"
        } else if let icon = tool.iconName, !icon.isEmpty {
            return icon
        }
        return "wrench.and.screwdriver"
    }

    private func toolActionDescription(for tool: ToolActivityItem) -> String {
        if tool.status == .completed, let completedLabel = tool.completedLabel, !completedLabel.isEmpty {
            return completedLabel
        }
        if let displayLabel = tool.displayLabel, !displayLabel.isEmpty {
            return displayLabel
        }
        if !tool.argumentsSummary.isEmpty {
            let base = tool.purpose.isEmpty ? tool.toolId : tool.purpose
            return "\(base) · \(tool.argumentsSummary)"
        }
        if !tool.purpose.isEmpty {
            return tool.purpose
        }
        return tool.toolId
    }

    private func displayOutput(for tool: ToolActivityItem) -> String {
        // Once the tool has finished, show its final result; streamed chunks are
        // only a live preview while it is still running.
        let isActive = tool.status == .running || tool.status == .pending || tool.status == .retrying
        let raw: String
        if isActive {
            raw = !tool.streamingOutput.isEmpty ? tool.streamingOutput : tool.result
        } else {
            raw = !tool.result.isEmpty ? tool.result : tool.streamingOutput
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Guard against printing raw serialized JSON envelopes or tool dictionaries
        if trimmed.hasPrefix("{") && trimmed.contains("\"toolId\"") {
            return ""
        }
        return trimmed
    }

    // MARK: - File Row

    @ViewBuilder
    private func fileRow(for file: FileActivityItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(file.operation.capitalized)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            Text(file.filePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if file.addedLines > 0 {
                Text("+\(file.addedLines)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green)
            }
            if file.deletedLines > 0 {
                Text("-\(file.deletedLines)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Terminal Row

    @ViewBuilder
    private func terminalRow(for term: TerminalActivityItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: term.status == .completed ? "checkmark" : (term.status == .failed ? "xmark" : "terminal"))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(term.status == .completed ? Color.green : (term.status == .failed ? Color.red : Color.accentColor))

                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(term.command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()
            }

            if !term.output.isEmpty {
                Text(term.output.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 18)
            }
        }
    }

    // MARK: - Build Row

    @ViewBuilder
    private func buildRow(for build: BuildActivityItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: build.status == .completed ? "checkmark" : (build.status == .failed ? "xmark" : "hammer"))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(build.status == .completed ? Color.green : (build.status == .failed ? Color.red : Color.accentColor))

            Image(systemName: "hammer")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(build.status == .completed ? "Build succeeded" : (build.status == .failed ? "Build failed (\(build.errorCount) errors)" : "Building project"))
                .font(.system(size: 11))
                .foregroundStyle(build.status == .failed ? .red : .primary)

            Spacer()

            if build.duration > 0 {
                Text(String(format: "%.1fs", build.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Test Row

    @ViewBuilder
    private func testRow(for test: TestActivityItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: test.failedCount == 0 ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(test.failedCount == 0 ? Color.green : Color.red)

            Image(systemName: "play")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text("\(test.suiteName): \(test.passedCount) passed\(test.failedCount > 0 ? ", \(test.failedCount) failed" : "")")
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            Spacer()

            if test.duration > 0 {
                Text(String(format: "%.1fs", test.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Worker Row

    @ViewBuilder
    private func workerRow(for worker: WorkerActivityItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: worker.status == .completed ? "checkmark" : (worker.status == .failed ? "xmark" : "person.2"))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(worker.status == .completed ? Color.green : (worker.status == .failed ? Color.red : Color.accentColor))

            Text(worker.userFacingTitle)
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            Spacer()

            Text(worker.status.rawValue)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Recovery Row

    @ViewBuilder
    private func recoveryRow(for recovery: RecoveryActivityItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: recovery.isResolved ? "checkmark" : "arrow.counterclockwise")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(recovery.isResolved ? Color.green : Color.orange)

            Text(recovery.isResolved ? "Resolved \(recovery.domain)" : "Retrying \(recovery.domain)")
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            Spacer()

            Text("\(recovery.attemptNumber)/\(recovery.maxAttempts)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Verification Row

    @ViewBuilder
    private func verificationRow(for verification: VerificationActivityItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: verification.isPassed ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(verification.isPassed ? Color.green : Color.red)

            Text(verification.checkName)
                .font(.system(size: 11))
                .foregroundStyle(.primary)

            Spacer()

            Text(verification.details)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
