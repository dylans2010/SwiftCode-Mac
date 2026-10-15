//
//  MetaAssistToolsUI.swift
//  SwiftCode
//
//  Dedicated Tool Calls and Thinking UI for "Assist with Meta" (Muse SDK).
//  Faithfully styled after the Muse Desktop architecture (robzilla1738/muse-desktop).
//

import SwiftUI
import AppKit

// MARK: - Meta Assist Tools UI Root View

/// Main tools activity view for Assist with Meta (Muse SDK turns).
/// Groups 3 or more completed tools into a collapsible ToolGroup,
/// and renders individual ToolItems with inputs, outputs, diff badges, and execution metrics.
public struct MetaAssistToolsUI: View {
    public let activityGroup: AssistActivityGroup

    public init(activityGroup: AssistActivityGroup) {
        self.activityGroup = activityGroup
    }

    public var body: some View {
        let tools = activityGroup.tools
        let fileItems = activityGroup.files

        VStack(alignment: .leading, spacing: 8) {
            if tools.isEmpty && !activityGroup.hasContent {
                EmptyView()
            } else {
                let groupedEntries = computeGroupedEntries(from: tools)

                ForEach(groupedEntries) { entry in
                    switch entry {
                    case .single(let tool):
                        MetaAssistToolItemView(tool: tool, fileDiffs: fileItems)
                    case .group(let id, let toolList):
                        MetaAssistToolGroupView(id: id, tools: toolList, fileDiffs: fileItems)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func computeGroupedEntries(from items: [ToolActivityItem]) -> [GroupedToolEntry] {
        var entries: [GroupedToolEntry] = []
        var completedBuffer: [ToolActivityItem] = []

        for item in items {
            let isCompleted = item.status == .completed
            if isCompleted {
                completedBuffer.append(item)
            } else {
                if !completedBuffer.isEmpty {
                    if completedBuffer.count >= 3 {
                        let groupId = completedBuffer.first?.id.uuidString ?? UUID().uuidString
                        entries.append(.group(id: groupId, tools: completedBuffer))
                    } else {
                        for c in completedBuffer {
                            entries.append(.single(c))
                        }
                    }
                    completedBuffer.removeAll()
                }
                entries.append(.single(item))
            }
        }

        if !completedBuffer.isEmpty {
            if completedBuffer.count >= 3 {
                let groupId = completedBuffer.first?.id.uuidString ?? UUID().uuidString
                entries.append(.group(id: groupId, tools: completedBuffer))
            } else {
                for c in completedBuffer {
                    entries.append(.single(c))
                }
            }
        }

        return entries
    }
}

// MARK: - Grouped Tool Entries Helper

private enum GroupedToolEntry: Identifiable {
    case single(ToolActivityItem)
    case group(id: String, tools: [ToolActivityItem])

    var id: String {
        switch self {
        case .single(let tool): return tool.id.uuidString
        case .group(let id, _): return id
        }
    }
}

// MARK: - Single Tool Item View (Muse Desktop ToolItem Replica)

public struct MetaAssistToolItemView: View {
    public let tool: ToolActivityItem
    public let fileDiffs: [FileActivityItem]

    @State private var isOpen: Bool = false
    @State private var copiedInput: Bool = false
    @State private var copiedOutput: Bool = false

    public init(tool: ToolActivityItem, fileDiffs: [FileActivityItem] = []) {
        self.tool = tool
        self.fileDiffs = fileDiffs
    }

    private var isRunning: Bool {
        tool.status == .running || tool.status == .retrying
    }

    private var toolTitle: String {
        if let label = tool.displayLabel, !label.isEmpty, !isRawInternalIdentifier(label) {
            return label
        }
        return humanReadableTitle(for: tool.toolId)
    }

    private func isRawInternalIdentifier(_ text: String) -> Bool {
        let raw = text.lowercased()
        return raw.contains("plan-askuser") ||
               raw.contains("code_replace") ||
               raw.contains("use_terminal") ||
               raw.contains("file_read") ||
               raw.contains("file_write") ||
               raw.contains("file_create") ||
               raw.contains("dir_read") ||
               raw.contains("search_text") ||
               raw.contains("agent_subagent_start") ||
               raw.contains("dispatch_")
    }

    private func humanReadableTitle(for id: String) -> String {
        let normalized = id.lowercased().replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "file_read", "read_file", "view_file":
            return "Reading project files"
        case "file_write", "write_file", "file_create", "create_file":
            return "Writing project files"
        case "code_replace", "edit_file", "replace_in_file":
            return "Editing project files"
        case "use_terminal", "run_command", "terminal_command":
            return "Running terminal command"
        case "dir_read", "list_dir", "list_directory":
            return "Reading directory"
        case "search_text", "search_dir", "find_file":
            return "Searching codebase"
        case "plan_askuser", "plan-askuser":
            return "Preparing decision prompt"
        case "use_workers", "start_subagent":
            return "Delegating task to worker"
        case "build_project":
            return "Building project"
        case "run_tests", "test_runner":
            return "Running tests"
        case "execution_plan":
            return "Preparing execution plan"
        default:
            let title = id.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
            return title
        }
    }

    private var toolSummary: String? {
        if !tool.purpose.isEmpty && tool.purpose != toolTitle {
            return tool.purpose
        }
        if let msg = tool.progressMessage, !msg.isEmpty {
            return msg
        }
        return nil
    }

    private var matchingFileDiff: FileActivityItem? {
        fileDiffs.first { file in
            let name = (file.filePath as NSString).lastPathComponent
            return tool.purpose.contains(file.filePath) ||
                   tool.purpose.contains(name) ||
                   tool.result.contains(file.filePath) ||
                   tool.result.contains(name)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header summary button
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Tool state indicator
                    statusIndicator(status: tool.status)

                    // Tool kind icon
                    toolKindIcon(for: tool.toolId)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)

                    // Title
                    Text(toolTitle)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    // Subtitle / status summary
                    if let summary = toolSummary {
                        Text(summary)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    // Diff badge if available
                    if let diff = matchingFileDiff, (diff.addedLines > 0 || diff.deletedLines > 0) {
                        HStack(spacing: 4) {
                            Text("+\(diff.addedLines)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.green)
                            Text("−\(diff.deletedLines)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.red.opacity(0.85))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }

                    // Rotating Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Collapsible body
            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .opacity(0.4)

                    // Objective / Description
                    if !tool.purpose.isEmpty {
                        Text(tool.purpose)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // Input / Arguments
                    if let formattedArgs = formattedArguments(from: tool.semanticKey ?? "") ?? formattedArguments(from: tool.purpose), !formattedArgs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("INPUT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                copyButton(text: formattedArgs, isCopied: $copiedInput)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(formattedArgs)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.primary.opacity(0.9))
                                    .textSelection(.enabled)
                                    .padding(8)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                    }

                    // Output / Result
                    if !tool.result.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("OUTPUT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                copyButton(text: tool.result, isCopied: $copiedOutput)
                            }
                            ScrollView(.vertical) {
                                Text(tool.result)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 180)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                    }

                    // Status and duration pill
                    HStack(spacing: 6) {
                        Text(tool.status.rawValue.lowercased())
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)

                        if tool.duration > 0 {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text(String(format: "%.1fs", tool.duration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private func statusIndicator(status: ActivityStatus) -> some View {
        switch status {
        case .running, .retrying:
            ProgressView()
                .scaleEffect(0.4)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.green)
                .frame(width: 14, height: 14)
        case .failed, .cancelled:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.red)
                .frame(width: 14, height: 14)
        case .pending, .skipped:
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
                .frame(width: 14, height: 14)
        }
    }

    @ViewBuilder
    private func toolKindIcon(for name: String) -> some View {
        let lower = name.lowercased()
        if lower.contains("subagent") || lower.contains("worker") {
            Image(systemName: "person.2")
                .font(.system(size: 11))
        } else if lower.contains("shell") || lower.contains("bash") || lower.contains("terminal") || lower.contains("command") {
            Image(systemName: "terminal")
                .font(.system(size: 11))
        } else if lower.contains("file") || lower.contains("edit") || lower.contains("write") || lower.contains("read") {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
        } else if lower.contains("build") || lower.contains("test") {
            Image(systemName: "hammer")
                .font(.system(size: 11))
        } else {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 11))
        }
    }

    private func copyButton(text: String, isCopied: Binding<Bool>) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            isCopied.wrappedValue = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                isCopied.wrappedValue = false
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: isCopied.wrappedValue ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9))
                Text(isCopied.wrappedValue ? "Copied" : "Copy")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(isCopied.wrappedValue ? Color.green : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func formattedArguments(from raw: String) -> String? {
        guard !raw.isEmpty, raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            return nil
        }
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
              let str = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return str
    }
}

// MARK: - Tool Group View (Muse Desktop ToolGroup Replica)

public struct MetaAssistToolGroupView: View {
    public let id: String
    public let tools: [ToolActivityItem]
    public let fileDiffs: [FileActivityItem]

    @State private var isOpen: Bool = false

    public init(id: String, tools: [ToolActivityItem], fileDiffs: [FileActivityItem] = []) {
        self.id = id
        self.tools = tools
        self.fileDiffs = fileDiffs
    }

    private var uniqueToolNames: String {
        let names = Array(Set(tools.map { $0.displayLabel ?? $0.toolId })).sorted()
        return names.prefix(3).joined(separator: ", ")
    }

    private var totalAdded: Int {
        fileDiffs.reduce(0) { $0 + $1.addedLines }
    }

    private var totalRemoved: Int {
        fileDiffs.reduce(0) { $0 + $1.deletedLines }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group Header Button
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.green)
                        .frame(width: 14, height: 14)

                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)

                    Text("Ran \(tools.count) tools")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text(uniqueToolNames)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if totalAdded > 0 || totalRemoved > 0 {
                        HStack(spacing: 4) {
                            Text("+\(totalAdded)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.green)
                            Text("−\(totalRemoved)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.red.opacity(0.85))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Group Expanded List
            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .opacity(0.4)
                        .padding(.bottom, 2)

                    ForEach(tools) { item in
                        MetaAssistToolItemView(tool: item, fileDiffs: fileDiffs)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.75)
        )
    }
}

// MARK: - Reasoning & Thinking UI (Muse Desktop ReasoningItem Replica)

/// Modern Reasoning & Thinking inspection component modeled after Muse Desktop's `ReasoningItem`.
/// Features clean summary header, animated breathing/spinning indicator while composing,
/// an accent vertical border, monospaced typography, and direct copy capability.
public struct MetaAssistThinkingUI: View {
    public let thinkingContent: String
    public let duration: TimeInterval?
    public let isStreaming: Bool

    @State private var isOpen: Bool = false
    @State private var isCopied: Bool = false

    public init(
        thinkingContent: String,
        duration: TimeInterval? = nil,
        isStreaming: Bool = false
    ) {
        self.thinkingContent = thinkingContent
        self.duration = duration
        self.isStreaming = isStreaming
    }

    private var summaryTitle: String {
        if isStreaming {
            return "Thinking…"
        }
        if let d = duration, d > 0 {
            return String(format: "Reasoning summary · %.1fs", d)
        }
        return "Reasoning summary"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header summary button
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    if isStreaming {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.green)
                            .frame(width: 14, height: 14)
                    }

                    Text(summaryTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isStreaming ? Color.accentColor : Color.secondary)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))

                    Spacer()

                    if isOpen {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(thinkingContent, forType: .string)
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                isCopied = false
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 8))
                                Text(isCopied ? "Copied" : "Copy")
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundStyle(isCopied ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Collapsible thinking body with Muse Desktop left accent line
            if isOpen {
                HStack(alignment: .top, spacing: 10) {
                    // Left accent border bar
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.8), Color.blue.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .frame(width: 2.5)
                        .cornerRadius(1.25)

                    ScrollView(.vertical) {
                        Text(thinkingContent)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 220)
                }
                .padding(.leading, 6)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
