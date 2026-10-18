//
//  MuseCallsNativeToolsUI.swift
//  SwiftCode
//
//  Dedicated modern UI displayed when calling SwiftCode's native tools.
//  Strictly hides raw JSON schemas and raw tool call payloads using `hidesToolSchemaOnUI`,
//  displaying only clean human-readable narrative, status, duration, diffs, collapsible cards,
//  and dedicated SF Symbols for EVERY registered tool.
//

import SwiftUI
import AppKit

// MARK: - Muse Calls Native Tools UI Root View

public struct MuseCallsNativeToolsUI: View {
    public let activityGroup: AssistActivityGroup
    @State private var expandedGroupIds: Set<String> = []
    @State private var showWorkersSheet: Bool = false

    public init(activityGroup: AssistActivityGroup) {
        self.activityGroup = activityGroup
    }

    public var body: some View {
        let tools = activityGroup.tools
        let fileItems = activityGroup.files

        if tools.isEmpty && !activityGroup.hasContent {
            EmptyView()
        } else {
            let nativeTools = tools.filter { !$0.isMuseSDKTool }
            let museTools = tools.filter { $0.isMuseSDKTool }

            VStack(alignment: .leading, spacing: 12) {
                // 1. SwiftCode Native Tools Section
                if !nativeTools.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        nativeHeaderBadge(
                            toolCount: nativeTools.count,
                            isExecuting: activityGroup.isExecuting && nativeTools.contains(where: { $0.status == .running })
                        )

                        let groups = ToolExecutionGroup.group(tools: nativeTools)
                        if groups.count <= 1 && nativeTools.count <= 2 {
                            ForEach(nativeTools) { tool in
                                MuseNativeToolCard(tool: tool, fileDiffs: fileItems)
                            }
                        } else {
                            ForEach(groups) { group in
                                stageGroupView(group: group, fileDiffs: fileItems)
                            }
                        }
                    }
                }

                // 2. Muse SDK Tools Section (Dedicated distinct UI)
                if !museTools.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        museHeaderBadge(
                            toolCount: museTools.count,
                            isExecuting: activityGroup.isExecuting && museTools.contains(where: { $0.status == .running })
                        )

                        VStack(spacing: 6) {
                            ForEach(museTools) { tool in
                                MuseSDKToolCall(tool: tool, fileDiffs: fileItems)
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.35), Color.cyan.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .sheet(isPresented: $showWorkersSheet) {
                WorkersMainView()
            }
        }
    }

    @ViewBuilder
    private func stageGroupView(group: ToolExecutionGroup, fileDiffs: [FileActivityItem]) -> some View {
        let isExpanded = expandedGroupIds.contains(group.id) || group.isExecuting
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedGroupIds.remove(group.id)
                        } else {
                            expandedGroupIds.insert(group.id)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: group.stage.iconName)
                            .font(.caption)
                            .foregroundStyle(group.isExecuting ? Color.accentColor : Color.secondary)

                        Text(group.stage.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.primary)

                        Text("(\(group.summary))")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .buttonStyle(.plain)

                if group.stage == .workerExecution {
                    Button {
                        showWorkersSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "person.3.sequence.fill")
                                .font(.system(size: 9))
                            Text("Workers")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Open Assist Workers Dashboard")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(group.tools) { tool in
                        if tool.isMuseSDKTool {
                            MuseSDKToolCall(tool: tool, fileDiffs: fileDiffs)
                        } else {
                            MuseNativeToolCard(tool: tool, fileDiffs: fileDiffs)
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
    }

    @ViewBuilder
    private func nativeHeaderBadge(toolCount: Int, isExecuting: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.green)

            Text("SwiftCode Native Operations")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.green)

            if isExecuting {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            } else {
                Text("· \(toolCount) \(toolCount == 1 ? "operation" : "operations")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func museHeaderBadge(toolCount: Int, isExecuting: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.blue)

            Text("Muse Tool")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.blue)

            if isExecuting {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
            } else {
                Text("· \(toolCount) \(toolCount == 1 ? "tool" : "tools")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
               lower.contains("assisttoolregistry") ||
               lower.contains("type:") ||
               lower.contains("properties") ||
               lower.contains("schema")
    }

    // MARK: - Complex Schema Stripping & Humanization Function

    /// Complex function that fully strips down the tool schema from showing it on the UI.
    /// Transforms JSON schemas, argument dictionaries, and raw identifiers into clean,
    /// natural human-readable text for users without exposing raw schemas or internal IDs.
    public static func hidesToolSchemaOnUI(rawText: String, arguments: [String: Any] = [:], toolId: String = "") -> String {
        // 1. If arguments are present, construct a clean narrative from key domain parameters
        if !arguments.isEmpty {
            let normalizedId = toolId.lowercased().replacingOccurrences(of: "-", with: "_")

            if normalizedId.contains("file_read") || normalizedId.contains("read_file") || normalizedId.contains("view_file") {
                if let path = arguments["path"] as? String ?? arguments["targetFile"] as? String ?? arguments["file"] as? String {
                    let filename = (path as NSString).lastPathComponent
                    return "Inspecting contents of \(filename)"
                }
            } else if normalizedId.contains("file_write") || normalizedId.contains("write_file") || normalizedId.contains("file_create") {
                if let path = arguments["path"] as? String ?? arguments["targetFile"] as? String ?? arguments["file"] as? String {
                    let filename = (path as NSString).lastPathComponent
                    return "Writing file content to \(filename)"
                }
            } else if normalizedId.contains("code_replace") || normalizedId.contains("replace_in_file") {
                if let path = arguments["path"] as? String ?? arguments["targetFile"] as? String ?? arguments["file"] as? String {
                    let filename = (path as NSString).lastPathComponent
                    return "Applying targeted code modifications to \(filename)"
                }
            } else if normalizedId.contains("use_terminal") || normalizedId.contains("terminal") || normalizedId.contains("bash") || normalizedId.contains("sh") || normalizedId.contains("zsh") {
                if let cmd = arguments["command"] as? String ?? arguments["CommandLine"] as? String {
                    let trimmedCmd = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
                    return "Executing command: \(trimmedCmd.prefix(80))"
                }
            } else if normalizedId.contains("use_workers") || normalizedId.contains("workers") || normalizedId.contains("workflow") {
                if let workers = arguments["workers"] as? [[String: Any]] {
                    return "Coordinating \(workers.count) parallel workers across distinct tasks"
                }
                return "Orchestrating autonomous background workers"
            } else if normalizedId.contains("plan_askuser") || normalizedId.contains("askuser") {
                if let q = arguments["question"] as? String {
                    return "Requesting user decision: \(q.prefix(80))"
                }
                return "Prompting user for decision clarification"
            } else if normalizedId.contains("report_to_user") {
                return "Delivering final task report to user"
            } else if normalizedId.contains("search") || normalizedId.contains("grep") {
                if let query = arguments["query"] as? String ?? arguments["pattern"] as? String {
                    return "Searching codebase for \"\(query)\""
                }
            }
        }

        // 2. If rawText is provided, strip schema artifacts, JSON brackets, and internal tool signatures
        var cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip JSON schema keywords and markdown code fences
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        let schemaKeywords = [
            "\"type\": \"object\"",
            "\"properties\":",
            "\"required\":",
            "\"parameters\":",
            "\"schema\":",
            "\"description\":",
            "\"items\":"
        ]

        var hasSchemaMarker = false
        for kw in schemaKeywords {
            if cleaned.contains(kw) {
                hasSchemaMarker = true
                break
            }
        }

        if hasSchemaMarker {
            // Attempt to parse out human-friendly values rather than dumping schema
            if let data = cleaned.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let desc = json["description"] as? String, !desc.isEmpty {
                    return desc
                }
                if let msg = json["message"] as? String, !msg.isEmpty {
                    return msg
                }
            }
            // Strip raw braces and quotes if json parsing was ambiguous
            cleaned = cleaned.replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(of: "}", with: "")
                .replacingOccurrences(of: "\"", with: "")
        }

        // Remove raw internal IDs from text
        cleaned = cleaned.replacingOccurrences(of: "file_read", with: "file read")
            .replacingOccurrences(of: "file_write", with: "file write")
            .replacingOccurrences(of: "code_replace", with: "code edit")
            .replacingOccurrences(of: "use_terminal", with: "terminal")
            .replacingOccurrences(of: "plan-AskUser", with: "decision prompt")
            .replacingOccurrences(of: "use_workers", with: "worker coordination")
            .replacingOccurrences(of: "report_to_user", with: "task report")

        return cleaned.isEmpty ? "Operation completed" : cleaned
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
        case "search_text", "search_regex", "grep_search":
            return "Searching Codebase"
        case "search_symbol":
            return "Finding Symbol Definition"
        case "project_build", "build_project":
            return "Building Xcode Project"
        case "project_test", "run_tests", "test_runner":
            return "Running Test Suite"
        case "use_terminal", "run_command", "terminal", "bash", "sh", "zsh":
            return "Executing Terminal Command"
        case "use_workers", "workers", "workflow":
            return "Coordinating Assist Workers"
        case "report_to_user":
            return "Presenting Task Completion"
        case "plan_askuser", "plan-askuser", "askuser":
            return "Decision Point Requested"
        case "mcp_call", "use_mcp":
            return "Executing MCP Integration"
        case "composio_execute", "use_composio":
            return "Executing Composio Tool"
        case "git_status":
            return "Checking Git Status"
        case "git_commit":
            return "Committing Changes"
        case "git_push":
            return "Pushing to Git Remote"
        default:
            let cleaned = rawId
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
            return cleaned.isEmpty ? "Executing Action" : cleaned
        }
    }

    // MARK: - SF Symbols for EVERY Tool

    public static func sfSymbol(for toolId: String) -> String {
        let norm = toolId.lowercased().replacingOccurrences(of: "-", with: "_")
        switch norm {
        case "file_read", "read_file", "view_file":
            return "doc.text.magnifyingglass"
        case "file_write", "write_file", "file_create", "create_file":
            return "doc.badge.plus"
        case "file_delete", "delete_file":
            return "trash.fill"
        case "code_replace", "replace_in_file":
            return "text.badge.checkmark"
        case "code_insert", "insert_code":
            return "character.cursor.ibeam"
        case "code_format", "format_code":
            return "wand.and.stars"
        case "code_lint", "lint_code":
            return "checkmark.shield.fill"
        case "dir_read", "list_dir", "list_directory":
            return "folder.fill"
        case "dir_create", "create_directory":
            return "folder.badge.plus"
        case "tree_view":
            return "list.bullet.indent"
        case "search_text", "search_regex", "grep_search":
            return "magnifyingglass"
        case "search_symbol":
            return "curlybraces"
        case "project_build", "build_project":
            return "hammer.fill"
        case "project_test", "run_tests", "test_runner":
            return "play.circle.fill"
        case "use_terminal", "run_command", "terminal", "bash", "sh", "zsh":
            return "terminal.fill"
        case "use_workers", "workers", "workflow":
            return "person.3.sequence.fill"
        case "report_to_user":
            return "bubble.left.and.exclamationmark.bubble.right.fill"
        case "plan_askuser", "plan-askuser", "askuser":
            return "questionmark.bubble.fill"
        case "mcp_call", "use_mcp":
            return "network"
        case "composio_execute", "use_composio":
            return "app.connected.to.app.below.fill"
        case "git_status", "git_commit", "git_push", "git_diff":
            return "arrow.triangle.branch"
        default:
            if norm.contains("worker") { return "person.3.sequence.fill" }
            if norm.contains("file") { return "doc.text.fill" }
            if norm.contains("code") { return "chevron.left.forwardslash.chevron.right" }
            if norm.contains("term") || norm.contains("shell") { return "terminal.fill" }
            if norm.contains("build") { return "hammer.fill" }
            if norm.contains("test") { return "play.circle.fill" }
            return "wrench.and.screwdriver.fill"
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
                params.append((key: "Details", value: Self.hidesToolSchemaOnUI(rawText: tool.purpose, toolId: tool.toolId)))
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
               lower == "json" ||
               lower == "parametersschema"
    }

    private func humanizeParamKey(_ key: String) -> String {
        switch key.lowercased() {
        case "path", "filepath", "file_path", "targetfile":
            return "File"
        case "command", "cmd", "commandline":
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
        case "workers":
            return "Workers"
        case "summary":
            return "Summary"
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

    private var isWorkerTool: Bool {
        let norm = tool.toolId.lowercased().replacingOccurrences(of: "-", with: "_")
        return norm == "use_workers" || norm == "workers" || norm == "workflow"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Summary Row Button (Collapsible trigger)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Status Icon
                    statusIcon

                    // Tool Kind SF Symbol (Explicitly mapped for every tool)
                    Image(systemName: Self.sfSymbol(for: tool.toolId))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor.opacity(0.9))
                        .frame(width: 16, height: 16)

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

            // Expanded Collapsible Details Card
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .opacity(0.35)

                    // Human-Readable Narrative (Stripping raw schemas)
                    let narrative = Self.hidesToolSchemaOnUI(rawText: tool.purpose, toolId: tool.toolId)
                    if !narrative.isEmpty && narrative != displayTitle {
                        Text(narrative)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .padding(.horizontal, 4)
                    }

                    // Specialized Worker Card if this is a `use_workers` invocation
                    if isWorkerTool {
                        workerOrchestrationDetailsView
                    }

                    // Clean Parameters View (No Schemas, Only Values)
                    if !cleanParameters.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ACTION PARAMETERS")
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
                                Text("OUTCOME")
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

    // MARK: - Dedicated Worker Orchestration Subview

    @ViewBuilder
    private var workerOrchestrationDetailsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.blue)

                Text("PARALLEL WORKER DISPATCH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)

                Spacer()
            }

            Text("Assist coordinated multiple subagent workers to execute scoped subtasks in parallel without cross-worker file collision.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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

    private func cleanOutputText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") && text.hasSuffix("}") {
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let output = json["output"] as? String {
                    return output
                }
                if let msg = json["message"] as? String {
                    return msg
                }
                if let res = json["result"] as? String {
                    return res
                }
            }
        }
        return text
    }
}
