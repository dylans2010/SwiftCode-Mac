//
//  MuseCallsNativeToolsUI.swift
//  SwiftCode
//
//  Dedicated UI displayed when Muse models call SwiftCode's native tools.
//  Strictly hides raw JSON schemas and raw tool call payloads, displaying
//  only relevant human-readable information, clean parameters, status, and results.
//

import SwiftUI
import AppKit

// MARK: - Muse Calls Native Tools UI

public struct MuseCallsNativeToolsUI: View {
    public let activityGroup: AssistActivityGroup

    public init(activityGroup: AssistActivityGroup) {
        self.activityGroup = activityGroup
    }

    public var body: some View {
        let tools = activityGroup.tools
        let fileItems = activityGroup.files

        if tools.isEmpty && !activityGroup.hasContent {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Section Header Badge
                headerBadge(toolCount: tools.count, isExecuting: activityGroup.isExecuting)

                // Tool Cards
                ForEach(tools) { tool in
                    MuseNativeToolCard(tool: tool, fileDiffs: fileItems)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func headerBadge(toolCount: Int, isExecuting: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Native Tool Execution")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)

            if isExecuting {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            } else {
                Text("· \(toolCount) \(toolCount == 1 ? "action" : "actions")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Muse Native Tool Card

public struct MuseNativeToolCard: View {
    public let tool: ToolActivityItem
    public let fileDiffs: [FileActivityItem]

    @State private var isOpen: Bool = false
    @State private var isResultExpanded: Bool = false
    @State private var isCopied: Bool = false

    public init(tool: ToolActivityItem, fileDiffs: [FileActivityItem] = []) {
        self.tool = tool
        self.fileDiffs = fileDiffs
    }

    private var isRunning: Bool {
        tool.status == .running || tool.status == .retrying
    }

    private var displayTitle: String {
        if let label = tool.displayLabel, !label.isEmpty, !isRawIdentifier(label) {
            return label
        }
        return humanReadableTitle(for: tool.toolId)
    }

    private func isRawIdentifier(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("file_") ||
               lower.contains("code_") ||
               lower.contains("dir_") ||
               lower.contains("use_terminal") ||
               lower.contains("plan-askuser") ||
               lower.contains("AssistToolRegistry") ||
               lower.contains("type:")
    }

    private func humanReadableTitle(for rawId: String) -> String {
        let norm = rawId.lowercased().replacingOccurrences(of: "-", with: "_")
        switch norm {
        case "file_read", "read_file", "view_file":
            return "Reading File Content"
        case "file_write", "write_file":
            return "Writing File Content"
        case "file_create", "create_file":
            return "Creating New File"
        case "file_delete", "delete_file":
            return "Deleting File"
        case "code_replace", "replace_in_file":
            return "Applying Code Edit"
        case "code_insert", "insert_code":
            return "Inserting Code Block"
        case "code_format", "format_code":
            return "Formatting Code"
        case "code_lint", "lint_code":
            return "Linting Code"
        case "dir_read", "list_dir", "list_directory":
            return "Inspecting Directory Structure"
        case "dir_create", "create_directory":
            return "Creating Directory"
        case "tree_view":
            return "Inspecting Workspace Tree"
        case "search_text", "search_regex":
            return "Searching Codebase"
        case "search_symbol":
            return "Finding Symbol Definition"
        case "project_build", "build_project":
            return "Building Xcode Project"
        case "project_test", "run_tests", "test_runner":
            return "Running Test Suite"
        case "use_terminal", "run_command":
            return "Executing Terminal Command"
        case "plan_askuser", "plan-askuser":
            return "Decision Point Requested"
        default:
            let cleaned = rawId
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
            return cleaned.isEmpty ? "Executing Tool" : cleaned
        }
    }

    private var cleanParameters: [(key: String, value: String)] {
        var params: [(key: String, value: String)] = []

        // Extract clean key-values from semantic key or purpose, strictly ignoring raw schemas
        if let semKey = tool.semanticKey, !semKey.isEmpty {
            let parts = semKey.components(separatedBy: "|")
            for part in parts.dropFirst() {
                let kv = part.components(separatedBy: ":")
                if kv.count >= 2 {
                    let k = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let v = kv.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !isIgnoredParameterKey(k) && !v.isEmpty {
                        params.append((key: humanizeParamKey(k), value: cleanParamValue(v)))
                    }
                }
            }
        }

        // If semantic key had no structured params, attempt to extract relevant path or command
        if params.isEmpty {
            if let extractedPath = extractRelevantPath(from: tool.purpose) {
                params.append((key: "Target", value: extractedPath))
            } else if !tool.purpose.isEmpty && tool.purpose != displayTitle {
                params.append((key: "Details", value: tool.purpose))
            }
        }

        return params
    }

    private func isIgnoredParameterKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower == "schema" ||
               lower == "parameters" ||
               lower == "type" ||
               lower == "properties" ||
               lower == "required" ||
               lower == "json"
    }

    private func humanizeParamKey(_ key: String) -> String {
        switch key.lowercased() {
        case "path", "filepath", "file_path", "targetfile":
            return "File"
        case "command", "cmd":
            return "Command"
        case "target", "find", "old_string":
            return "Pattern"
        case "replacement", "replace", "new_string":
            return "Replacement"
        case "query":
            return "Search"
        case "directory", "dir":
            return "Directory"
        case "line":
            return "Line"
        default:
            return key.capitalized
        }
    }

    private func cleanParamValue(_ val: String) -> String {
        var clean = val
        if clean.hasPrefix("\"") && clean.hasSuffix("\"") && clean.count >= 2 {
            clean = String(clean.dropFirst().dropLast())
        }
        return clean.replacingOccurrences(of: "\\n", with: "\n")
    }

    private func extractRelevantPath(from text: String) -> String? {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words.first { word in
            word.contains(".") && !word.hasPrefix("http") && !word.contains("...")
        }
    }

    private var matchingDiff: FileActivityItem? {
        fileDiffs.first { item in
            tool.purpose.contains(item.filePath) ||
            tool.result.contains(item.filePath) ||
            (tool.semanticKey?.contains(item.filePath) ?? false)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Summary Row Button
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Status Icon
                    statusIcon

                    // Tool Kind Icon
                    toolKindIcon
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                        .frame(width: 14, height: 14)

                    // Human-Readable Title
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    // Key Parameter Pills (Clean Target Info)
                    if let firstParam = cleanParameters.first {
                        Text("\(firstParam.key): \(firstParam.value)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer(minLength: 4)

                    // Diffs Indicator Badge
                    if let diff = matchingDiff, (diff.addedLines > 0 || diff.deletedLines > 0) {
                        HStack(spacing: 3) {
                            if diff.addedLines > 0 {
                                Text("+\(diff.addedLines)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.green)
                            }
                            if diff.deletedLines > 0 {
                                Text("−\(diff.deletedLines)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.red.opacity(0.85))
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                    }

                    // Duration Tag
                    if tool.duration > 0 {
                        Text(String(format: "%.1fs", tool.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    // Rotation Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded Details View
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .opacity(0.35)

                    // Clean Parameters View (No Schemas, Only Values)
                    if !cleanParameters.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PARAMETERS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            ForEach(cleanParameters, id: \.key) { param in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(param.key):")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Text(param.value)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.primary.opacity(0.9))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 1)
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                    }

                    // Clean Output Result (Formatted Text, Fully Scrollable)
                    if !tool.result.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("RESULT")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.tertiary)

                                Spacer()

                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isResultExpanded.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: isResultExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                            .font(.system(size: 8))
                                        Text(isResultExpanded ? "Collapse" : "Expand All")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(tool.result, forType: .string)
                                    isCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                        isCopied = false
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 8))
                                        Text(isCopied ? "Copied" : "Copy")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                }
                                .buttonStyle(.plain)
                            }

                            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                Text(cleanOutputText(tool.result))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: isResultExpanded ? .infinity : 240)
                            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.status {
        case .running, .retrying:
            ProgressView()
                .scaleEffect(0.35)
                .frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.green)
                .frame(width: 14, height: 14)
        case .failed, .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
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
    private var toolKindIcon: some View {
        let lower = tool.toolId.lowercased()
        if lower.contains("file") || lower.contains("read") || lower.contains("write") {
            Image(systemName: "doc.text.fill")
        } else if lower.contains("code") || lower.contains("edit") || lower.contains("replace") {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
        } else if lower.contains("search") || lower.contains("find") {
            Image(systemName: "magnifyingglass")
        } else if lower.contains("build") || lower.contains("test") {
            Image(systemName: "hammer.fill")
        } else if lower.contains("terminal") || lower.contains("command") {
            Image(systemName: "terminal.fill")
        } else {
            Image(systemName: "gearshape.2.fill")
        }
    }

    private func cleanOutputText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // If it starts with JSON syntax, format cleanly without raw schema markers
        if text.hasPrefix("{") && text.hasSuffix("}") {
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // If there is an output or result field, extract that directly
                if let output = json["output"] as? String {
                    return output
                }
                if let msg = json["message"] as? String {
                    return msg
                }
            }
        }
        return text
    }
}
