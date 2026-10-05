//
//  AssistToolActivityFormatter.swift
//  SwiftCode
//
//  Transforms raw tool invocations and parameters into concise, human-readable
//  activity representations with context (e.g. "Reading App.swift", "Building project").
//

import Foundation

public struct ToolFormattedActivity: Sendable {
    public let runningLabel: String
    public let completedLabel: String
    public let failedLabel: String
    public let iconName: String

    public init(
        runningLabel: String,
        completedLabel: String,
        failedLabel: String,
        iconName: String
    ) {
        self.runningLabel = runningLabel
        self.completedLabel = completedLabel
        self.failedLabel = failedLabel
        self.iconName = iconName
    }
}

public enum AssistToolActivityFormatter {
    /// Formats a tool invocation into concise human-readable activity strings.
    public static func format(toolId: String, arguments: [String: Any]) -> ToolFormattedActivity {
        let normalizedId = toolId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. File reading tools
        if ["file_read", "read_file", "view_file", "read_file_content", "file_view"].contains(normalizedId) {
            if let file = extractFilename(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Reading \(file)",
                    completedLabel: "Read \(file)",
                    failedLabel: "Failed to read \(file)",
                    iconName: "doc.text.magnifyingglass"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Reading project file",
                completedLabel: "Read project file",
                failedLabel: "Failed to read file",
                iconName: "doc.text.magnifyingglass"
            )
        }

        // 2. File creation & writing tools
        if ["file_write", "write_file", "write_to_file", "file_create", "create_file", "code_generate", "generate_file"].contains(normalizedId) {
            if let file = extractFilename(from: arguments) {
                let actionVerb = normalizedId.contains("create") || normalizedId.contains("generate") ? "Creating" : "Writing"
                let completedVerb = normalizedId.contains("create") || normalizedId.contains("generate") ? "Created" : "Wrote"
                return ToolFormattedActivity(
                    runningLabel: "\(actionVerb) \(file)",
                    completedLabel: "\(completedVerb) \(file)",
                    failedLabel: "Failed to write \(file)",
                    iconName: "square.and.pencil"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Writing file",
                completedLabel: "Wrote file",
                failedLabel: "Failed to write file",
                iconName: "square.and.pencil"
            )
        }

        // 3. File appending
        if ["file_append", "append_file"].contains(normalizedId) {
            if let file = extractFilename(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Appending to \(file)",
                    completedLabel: "Appended to \(file)",
                    failedLabel: "Failed to append to \(file)",
                    iconName: "text.append"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Appending to file",
                completedLabel: "Appended to file",
                failedLabel: "Failed to append to file",
                iconName: "text.append"
            )
        }

        // 4. File editing & replacing
        if ["code_replace", "replace_in_file", "replace_file_content", "multi_replace_file_content", "code_multi_edit", "code_insert", "insert_code_block", "code_refactor", "refactor", "code_format", "format_code", "patch_application_engine", "code_mutation_engine"].contains(normalizedId) {
            if let file = extractFilename(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Editing \(file)",
                    completedLabel: "Edited \(file)",
                    failedLabel: "Failed to edit \(file)",
                    iconName: "pencil"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Editing code",
                completedLabel: "Edited code",
                failedLabel: "Failed to edit code",
                iconName: "pencil"
            )
        }

        // 5. File deletion
        if ["file_delete", "delete_file"].contains(normalizedId) {
            if let file = extractFilename(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Deleting \(file)",
                    completedLabel: "Deleted \(file)",
                    failedLabel: "Failed to delete \(file)",
                    iconName: "trash"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Deleting file",
                completedLabel: "Deleted file",
                failedLabel: "Failed to delete file",
                iconName: "trash"
            )
        }

        // 6. File rename & move
        if ["file_rename", "rename_file", "file_move", "move_file"].contains(normalizedId) {
            if let file = extractFilename(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Renaming \(file)",
                    completedLabel: "Renamed \(file)",
                    failedLabel: "Failed to rename \(file)",
                    iconName: "arrow.right.arrow.left"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Renaming file",
                completedLabel: "Renamed file",
                failedLabel: "Failed to rename file",
                iconName: "arrow.right.arrow.left"
            )
        }

        // 7. File copy
        if ["file_copy", "copy_file"].contains(normalizedId) {
            if let file = extractFilename(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Copying \(file)",
                    completedLabel: "Copied \(file)",
                    failedLabel: "Failed to copy \(file)",
                    iconName: "doc.on.doc"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Copying file",
                completedLabel: "Copied file",
                failedLabel: "Failed to copy file",
                iconName: "doc.on.doc"
            )
        }

        // 8. Directory reading & tree view
        if ["dir_read", "read_directory", "list_dir", "list_directory", "tree_view"].contains(normalizedId) {
            if let dir = extractDirectoryName(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Inspecting \(dir)",
                    completedLabel: "Inspected \(dir)",
                    failedLabel: "Failed to inspect \(dir)",
                    iconName: "folder"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Inspecting directory structure",
                completedLabel: "Inspected directory structure",
                failedLabel: "Failed to inspect directory",
                iconName: "folder"
            )
        }

        // 9. Directory creation
        if ["dir_create", "create_directory"].contains(normalizedId) {
            if let dir = extractDirectoryName(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Creating directory \(dir)",
                    completedLabel: "Created directory \(dir)",
                    failedLabel: "Failed to create directory \(dir)",
                    iconName: "folder.badge.plus"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Creating directory",
                completedLabel: "Created directory",
                failedLabel: "Failed to create directory",
                iconName: "folder.badge.plus"
            )
        }

        // 10. Searching code & files
        if ["search_text", "grep_search", "search_code", "search_files", "search_regex", "regex_search", "search_symbol", "symbol_search"].contains(normalizedId) {
            if let query = extractSearchQuery(from: arguments) {
                return ToolFormattedActivity(
                    runningLabel: "Searching for '\(query)'",
                    completedLabel: "Searched for '\(query)'",
                    failedLabel: "Search failed for '\(query)'",
                    iconName: "magnifyingglass"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Searching project files",
                completedLabel: "Searched project files",
                failedLabel: "Search failed",
                iconName: "magnifyingglass"
            )
        }

        // 11. Build project
        if ["project_build", "build_project", "build", "xcodebuild"].contains(normalizedId) {
            let target = arguments["target"] as? String ?? arguments["scheme"] as? String
            let targetSuffix = target.map { " (\($0))" } ?? ""
            return ToolFormattedActivity(
                runningLabel: "Building project\(targetSuffix)...",
                completedLabel: "Build succeeded\(targetSuffix)",
                failedLabel: "Build failed\(targetSuffix)",
                iconName: "hammer.fill"
            )
        }

        // 12. Run tests
        if ["run_tests", "test_runner", "test", "tests"].contains(normalizedId) {
            let target = arguments["testTarget"] as? String ?? arguments["suite"] as? String
            let targetSuffix = target.map { " (\($0))" } ?? ""
            return ToolFormattedActivity(
                runningLabel: "Running tests\(targetSuffix)...",
                completedLabel: "Tests completed\(targetSuffix)",
                failedLabel: "Tests failed\(targetSuffix)",
                iconName: "checkmark.seal"
            )
        }

        // 13. Terminal commands (Task runner)
        if ["use_terminal", "task_runner", "run_command"].contains(normalizedId) {
            let rawCmd = arguments["command"] as? String ?? arguments["CommandLine"] as? String ?? arguments["cmd"] as? String ?? ""
            let safeLabel = sanitizeCommand(rawCmd)
            return ToolFormattedActivity(
                runningLabel: safeLabel.isEmpty ? "Running command..." : "Running \(safeLabel)",
                completedLabel: safeLabel.isEmpty ? "Command completed" : "\(safeLabel) completed",
                failedLabel: safeLabel.isEmpty ? "Command failed" : "\(safeLabel) failed",
                iconName: "terminal.fill"
            )
        }

        // 14. Workers / Subagents
        if ["use_workers", "start_subagent"].contains(normalizedId) {
            let workerName = arguments["name"] as? String ?? arguments["task"] as? String ?? arguments["TaskName"] as? String ?? arguments["workerName"] as? String
            if let name = workerName, !name.isEmpty {
                return ToolFormattedActivity(
                    runningLabel: "Started Worker: \(name)",
                    completedLabel: "Worker completed: \(name)",
                    failedLabel: "Worker failed: \(name)",
                    iconName: "cpu"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Running subagent...",
                completedLabel: "Subagent completed",
                failedLabel: "Subagent failed",
                iconName: "cpu"
            )
        }

        // 15. Execution Plan
        if ["execution_plan", "intel_plan_task", "intel_breakdown_task"].contains(normalizedId) {
            let objective = arguments["objective"] as? String ?? arguments["title"] as? String
            if let obj = objective, !obj.isEmpty {
                let cleanObj = obj.prefix(40)
                return ToolFormattedActivity(
                    runningLabel: "Formulating execution plan...",
                    completedLabel: "Execution plan created: \(cleanObj)",
                    failedLabel: "Failed to create plan",
                    iconName: "list.bullet.rectangle"
                )
            }
            return ToolFormattedActivity(
                runningLabel: "Formulating execution plan...",
                completedLabel: "Execution plan created",
                failedLabel: "Failed to create plan",
                iconName: "list.bullet.rectangle"
            )
        }

        // 16. Autonomous Code Review
        if ["code_review", "autonomous_review_engine"].contains(normalizedId) {
            return ToolFormattedActivity(
                runningLabel: "Autonomous code review in progress...",
                completedLabel: "Autonomous code review completed",
                failedLabel: "Code review reported issues",
                iconName: "checkmark.shield"
            )
        }

        // 17. Automated repair / compiler diagnostics
        if ["safe_validate_changes", "intel_autofix", "automated_repair_engine", "compiler_diagnostics_engine"].contains(normalizedId) {
            return ToolFormattedActivity(
                runningLabel: "Analyzing compiler diagnostics & repairing...",
                completedLabel: "Repairs verified",
                failedLabel: "Repair validation failed",
                iconName: "wrench.and.screwdriver"
            )
        }

        // 18. Create New App wizard
        if ["create_new_app"].contains(normalizedId) {
            let appName = arguments["appName"] as? String ?? "application"
            return ToolFormattedActivity(
                runningLabel: "Scaffolding \(appName)...",
                completedLabel: "Scaffolded \(appName)",
                failedLabel: "Failed to scaffold \(appName)",
                iconName: "sparkles"
            )
        }

        // 19. Dependency graph / resolution
        if ["dependency_graph", "dependency_resolution_engine"].contains(normalizedId) {
            return ToolFormattedActivity(
                runningLabel: "Resolving dependencies...",
                completedLabel: "Dependencies resolved",
                failedLabel: "Failed to resolve dependencies",
                iconName: "network"
            )
        }

        // 20. Log capture / Diagnostics
        if ["env_capture_logs", "runtime_diagnostics_engine"].contains(normalizedId) {
            return ToolFormattedActivity(
                runningLabel: "Capturing runtime diagnostics...",
                completedLabel: "Diagnostics captured",
                failedLabel: "Failed to capture diagnostics",
                iconName: "doc.plaintext"
            )
        }

        // 21. MCP / Composio
        if ["use_mcp"].contains(normalizedId) {
            let server = arguments["serverName"] as? String ?? arguments["server"] as? String ?? ""
            let tool = arguments["toolName"] as? String ?? ""
            let desc = !server.isEmpty && !tool.isEmpty ? "\(server)/\(tool)" : "tool"
            return ToolFormattedActivity(
                runningLabel: "Executing MCP \(desc)",
                completedLabel: "Executed MCP \(desc)",
                failedLabel: "MCP \(desc) failed",
                iconName: "puzzlepiece"
            )
        }
        if ["use_composio"].contains(normalizedId) {
            let action = arguments["action"] as? String ?? arguments["toolSlug"] as? String ?? ""
            return ToolFormattedActivity(
                runningLabel: action.isEmpty ? "Executing integration action" : "Executing \(action)",
                completedLabel: action.isEmpty ? "Integration action completed" : "\(action) completed",
                failedLabel: action.isEmpty ? "Integration action failed" : "\(action) failed",
                iconName: "link"
            )
        }

        // Fallback: Humanize snake_case or camelCase identifier
        let humanized = humanizeIdentifier(toolId)
        return ToolFormattedActivity(
            runningLabel: "Running \(humanized)...",
            completedLabel: "Completed \(humanized)",
            failedLabel: "Failed: \(humanized)",
            iconName: "gearshape"
        )
    }

    /// Extracts the file path from arguments dictionary.
    public static func extractFilePath(arguments: [String: Any]) -> String? {
        let candidateKeys = [
            "path", "filePath", "file", "targetPath", "destinationPath",
            "filename", "TargetFile", "AbsolutePath", "SearchPath", "url"
        ]
        for key in candidateKeys {
            if let val = arguments[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return val
            }
        }
        return nil
    }

    /// Extracts a user-facing filename or short relative path from arguments.
    public static func extractFilename(from arguments: [String: Any]) -> String? {
        guard let fullPath = extractFilePath(arguments: arguments) else { return nil }
        let url = URL(fileURLWithPath: fullPath)
        let last = url.lastPathComponent
        guard !last.isEmpty else { return nil }

        // If last component is generic, prefix with parent directory
        let parent = url.deletingLastPathComponent().lastPathComponent
        if ["main.swift", "app.swift", "index.ts", "main.py", "contentview.swift"].contains(last.lowercased()) && !parent.isEmpty && parent != "/" && parent != "." {
            return "\(parent)/\(last)"
        }
        return last
    }

    /// Extracts directory name from arguments.
    public static func extractDirectoryName(from arguments: [String: Any]) -> String? {
        let candidateKeys = ["path", "directory", "dir", "DirectoryPath", "SearchPath"]
        for key in candidateKeys {
            if let val = arguments[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let url = URL(fileURLWithPath: val)
                let last = url.lastPathComponent
                return last.isEmpty ? val : last
            }
        }
        return nil
    }

    /// Extracts a search query or pattern from arguments.
    public static func extractSearchQuery(from arguments: [String: Any]) -> String? {
        let candidateKeys = ["query", "pattern", "searchTerm", "text", "Query"]
        for key in candidateKeys {
            if let val = arguments[key] as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 32 {
                    return String(trimmed.prefix(30)) + "…"
                }
                return trimmed
            }
        }
        return nil
    }

    /// Determines the file operation name ("Created", "Modified", "Deleted") for a given tool.
    public static func determineFileOperation(toolId: String) -> String? {
        let lower = toolId.lowercased()
        if lower.contains("create") || lower.contains("generate") {
            return "Created"
        }
        if lower.contains("write") || lower.contains("replace") || lower.contains("edit") || lower.contains("append") || lower.contains("patch") {
            return "Modified"
        }
        if lower.contains("delete") || lower.contains("remove") {
            return "Deleted"
        }
        if lower.contains("rename") || lower.contains("move") {
            return "Renamed"
        }
        return nil
    }

    /// Sanitizes shell commands to never expose tokens, passwords, keys, or credentials,
    /// returning a clean human-readable summary.
    public static func sanitizeCommand(_ rawCommand: String) -> String {
        let trimmed = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Match well-known command patterns
        let lower = trimmed.lowercased()
        if lower.starts(with: "xcodebuild") || lower.contains("swift build") {
            return "build"
        }
        if lower.starts(with: "swift test") || lower.contains("xcodebuild test") {
            return "tests"
        }
        if lower.starts(with: "git status") {
            return "git status"
        }
        if lower.starts(with: "git diff") {
            return "git diff"
        }
        if lower.starts(with: "git log") {
            return "git log"
        }
        if lower.starts(with: "git commit") {
            return "git commit"
        }
        if lower.starts(with: "git push") {
            return "git push"
        }
        if lower.starts(with: "git ") {
            let parts = trimmed.split(separator: " ")
            if parts.count >= 2 {
                return "git \(parts[1])"
            }
            return "git"
        }
        if lower.starts(with: "killall") {
            let parts = trimmed.split(separator: " ")
            if parts.count >= 2 {
                return "killall \(parts[1])"
            }
            return "killall"
        }

        // Generic sanitization: strip tokens / secrets
        var safe = trimmed
        let secretPatterns = [
            "Bearer\\s+[A-Za-z0-9_\\-\\.]+",
            "(?i)(api[_-]?key|token|password|secret|key|passwd)\\s*[:=]\\s*['\"]?[^'\"\\s]+['\"]?"
        ]
        for pattern in secretPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: safe.utf16.count)
                safe = regex.stringByReplacingMatches(in: safe, options: [], range: range, withTemplate: "$1=***")
            }
        }

        // Return first 3-4 words or up to 35 chars
        let words = safe.split(separator: " ")
        if words.count > 4 {
            let truncated = words.prefix(4).joined(separator: " ")
            return "\(truncated)…"
        }
        if safe.count > 40 {
            return "\(safe.prefix(37))…"
        }
        return safe
    }

    /// Converts snake_case or camelCase identifiers into Title Case.
    private static func humanizeIdentifier(_ id: String) -> String {
        let spaced = id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)

        return spaced.capitalized
    }
}
