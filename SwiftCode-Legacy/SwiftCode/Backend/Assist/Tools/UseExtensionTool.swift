import Foundation

/// Assist interaction with installed SwiftCode extensions, both
/// ecosystems, through the real Extensions v2 platform — never a
/// simulated extension list or a fake command result.
///
/// Finite action set, selected by the required `action` parameter:
///   list, details, list_commands, list_xcode_commands, activate,
///   deactivate, execute, run_xcode_command, enable, disable,
///   diagnostics
///
/// How each ecosystem is actually used:
/// - VS Code extensions: `activate` starts the extension's real
///   out-of-process Node host (requires Node.js); `execute` runs one
///   of its contributed commands through that host, and with
///   confirm: true it activates first when the host is not running,
///   so one call works end to end. `list_commands` reads contributed
///   commands from the running host, or from the installed manifest
///   when the extension is not running.
/// - Xcode extensions: XcodeKit extension binaries themselves cannot
///   run inside SwiftCode (Xcode owns their packaging and
///   activation). What Assist can run is reusable source-editor
///   command logic registered in ExtV2XcodeCommandRegistry — the
///   built-in sort-lines command and any command registered by app
///   code or a native plugin. `run_xcode_command` reads a real
///   workspace file, builds a source buffer with the given selection
///   (or the whole file by default), runs the command against that
///   buffer, and writes the file back only when the buffer changed.
/// - SwiftCode-native plugins: `execute` routes their commands
///   through the native plugin registry, same as any other command.
///
/// Consequential actions (activate, execute, run_xcode_command,
/// enable, disable) require `confirm: true`, mirroring use_system's
/// confirm pattern: the model must explicitly confirm before
/// third-party code runs or a file changes. Read-only actions
/// (list, details, list_commands, list_xcode_commands, deactivate,
/// diagnostics) do not. This tool never launches anything itself;
/// all execution goes through ExtV2Manager and its host, so the
/// Extensions v2 permission checks, IPC allowlist, and crash
/// handling apply exactly as they do from the UI.
public struct UseExtensionTool: AssistTool {
    public let id = "use_extension"
    public let name = "Use Extension"
    public let description = "Interact with installed SwiftCode extensions: list, inspect, activate, and execute VS Code extension commands through the real extension host, and run Xcode-compatible source-editor commands against real workspace files. Actions: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics. Mutating actions (activate, execute, run_xcode_command, enable, disable) require confirm: true. Extension ids are stable publisher.name ids; Xcode command ids look like com.swiftcode.xcode.sortLines."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeMutation }
    public var requiredPermission: ToolPermissionRequirement { .fileSystem }

    public var supportedOperations: [String] {
        ["list", "details", "list_commands", "list_xcode_commands", "activate",
         "deactivate", "execute", "run_xcode_command", "enable", "disable", "diagnostics"]
    }

    public var knownLimitations: [String] {
        [
            "XcodeKit extension binaries cannot execute inside SwiftCode; only registered source-editor command logic runs via run_xcode_command.",
            "VS Code extension execution requires Node.js and an installed, enabled extension; language-provider contributions (completion, hover) are editor surfaces, not Assist-callable commands.",
            "Webview, terminal, and debug contributions are not rendered or driven through this tool.",
        ]
    }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs one extension action. Extension ids are stable publisher.name ids (list to discover them).",
            properties: [
                "action": JSONSchema(
                    type: "string",
                    description: "One of: list, details, list_commands, list_xcode_commands, activate, deactivate, execute, run_xcode_command, enable, disable, diagnostics."
                ),
                "extensionId": JSONSchema(
                    type: "string",
                    description: "Stable publisher.name id of the extension. Required for every action except list and list_xcode_commands."
                ),
                "command": JSONSchema(
                    type: "string",
                    description: "Command id for execute (a VS Code / native contributed command) or run_xcode_command (an Xcode command identifier, e.g. com.swiftcode.xcode.sortLines)."
                ),
                "file": JSONSchema(
                    type: "string",
                    description: "Workspace-relative path for run_xcode_command. Absolute paths and paths escaping the workspace are rejected."
                ),
                "selection": JSONSchema(
                    type: "object",
                    description: "Selection for run_xcode_command (0-based lines/columns). Defaults to the whole file.",
                    properties: [
                        "startLine": JSONSchema(type: "integer", description: "First line of the selection."),
                        "startColumn": JSONSchema(type: "integer", description: "First column of the selection."),
                        "endLine": JSONSchema(type: "integer", description: "Last line of the selection."),
                        "endColumn": JSONSchema(type: "integer", description: "Last column of the selection."),
                    ]
                ),
                "args": JSONSchema(
                    type: "object",
                    description: "String-keyed arguments passed to an execute command."
                ),
                "confirm": JSONSchema(
                    type: "boolean",
                    description: "Required true for activate, execute, run_xcode_command, enable, and disable; the model must explicitly confirm the consequential action."
                ),
                "limit": JSONSchema(
                    type: "integer",
                    description: "Max rows for list and diagnostics (default 50, capped at 200)."
                ),
            ],
            required: ["action"]
        )
    }

    private static let outputCap = 8_000

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            guard let actionRaw = input["action"] as? String,
                  let action = UseExtensionAction(rawValue: actionRaw) else {
                return .failure(
                    "Unknown or missing action. Use one of: \(UseExtensionAction.allCases.map(\.rawValue).joined(separator: ", ")).",
                    code: .invalidInput)
            }
            let extensionId = (input["extensionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let command = (input["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let file = (input["file"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let confirm = (input["confirm"] as? Bool) ?? false
            let limit = UseExtensionRouter.clampedLimit(input["limit"])
            let selection = UseExtensionRouter.parseSelection(input["selection"])
            let args = (input["args"] as? [String: Any]) ?? [:]
            try UseExtensionRouter.validate(
                action: action, extensionId: extensionId, command: command,
                file: file, confirm: confirm)
            let result = try await UseExtensionRouter.run(
                action: action, extensionId: extensionId, command: command,
                file: file, selection: selection, args: args, limit: limit,
                workspaceRoot: context.workspaceRoot)
            let output = UseExtensionRouter.capped(result.output)
            return .success(output, data: result.data, filesChanged: result.filesChanged)
        } catch let error as ExtV2Error {
            return .failure(error.localizedDescription, code: UseExtensionRouter.code(for: error))
        } catch {
            return .failure("use_extension failed: \(error.localizedDescription)", code: .executionFailed)
        }
    }
}

// MARK: - Actions

public enum UseExtensionAction: String, CaseIterable, Sendable {
    case list
    case details
    case listCommands = "list_commands"
    case listXcodeCommands = "list_xcode_commands"
    case activate
    case deactivate
    case execute
    case runXcodeCommand = "run_xcode_command"
    case enable
    case disable
    case diagnostics

    /// Actions that run third-party code or change state, and therefore
    /// require explicit confirmation.
    public var requiresConfirm: Bool {
        switch self {
        case .activate, .execute, .runXcodeCommand, .enable, .disable: return true
        default: return false
        }
    }

    public var requiresExtensionId: Bool {
        switch self {
        case .list, .listXcodeCommands: return false
        default: return true
        }
    }
}

public struct UseExtensionSelection: Sendable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
        self.startLine = startLine; self.startColumn = startColumn
        self.endLine = endLine; self.endColumn = endColumn
    }
}

public struct UseExtensionOutcome: Sendable {
    public let output: String
    public let data: [String: String]
    public let filesChanged: [String]

    public init(output: String, data: [String: String] = [:], filesChanged: [String] = []) {
        self.output = output; self.data = data; self.filesChanged = filesChanged
    }
}

// MARK: - Router (testable without an AssistContext)

/// The action implementations. Validation and the Xcode file
/// round-trip are pure enough to unit-test without a host, a
/// registry download, or an Assist session; VS Code paths delegate
/// to ExtV2Manager and fail honestly when no host is available.
@MainActor
public enum UseExtensionRouter {
    private static let outputCap = 8_000

    public static func clampedLimit(_ value: Any?) -> Int {
        let raw: Int?
        if let int = value as? Int { raw = int }
        else if let double = value as? Double { raw = Int(double) }
        else if let number = value as? NSNumber { raw = number.intValue }
        else { raw = nil }
        guard let raw else { return 50 }
        return min(max(raw, 1), 200)
    }

    public static func parseSelection(_ value: Any?) -> UseExtensionSelection? {
        guard let dict = value as? [String: Any] else { return nil }
        func int(_ key: String) -> Int? {
            if let v = dict[key] as? Int { return v }
            if let v = dict[key] as? Double { return Int(v) }
            return nil
        }
        guard let startLine = int("startLine"), let startColumn = int("startColumn"),
              let endLine = int("endLine"), let endColumn = int("endColumn") else { return nil }
        return UseExtensionSelection(
            startLine: startLine, startColumn: startColumn, endLine: endLine, endColumn: endColumn)
    }

    public static func capped(_ output: String) -> String {
        if output.count > outputCap {
            return String(output.prefix(outputCap)) + "\n... (truncated)"
        }
        return output
    }

    public static func code(for error: ExtV2Error) -> AssistToolErrorCode {
        switch error {
        case .notInstalled: return .notFound
        case .disabled, .permissionDenied: return .permissionDenied
        case .incompatible: return .unsupportedOperation
        case .missingDependencies: return .executionFailed
        case .invalidRequest: return .invalidInput
        case .timeout: return .timeout
        case .cancelled: return .cancelled
        default: return .executionFailed
        }
    }

    /// Validates an action's parameters before anything runs. Throws
    /// ExtV2Error.invalidRequest with a specific message; the tool
    /// maps it to AssistToolErrorCode.invalidInput.
    public static func validate(
        action: UseExtensionAction, extensionId: String?, command: String?,
        file: String?, confirm: Bool
    ) throws {
        if action.requiresExtensionId, (extensionId ?? "").isEmpty {
            throw ExtV2Error.invalidRequest("Action '\(action.rawValue)' requires extensionId.")
        }
        if action == .execute, (command ?? "").isEmpty {
            throw ExtV2Error.invalidRequest("Action 'execute' requires command.")
        }
        if action == .runXcodeCommand {
            guard let command, !command.isEmpty else {
                throw ExtV2Error.invalidRequest("Action 'run_xcode_command' requires command (an Xcode command identifier).")
            }
            guard let file, !file.isEmpty else {
                throw ExtV2Error.invalidRequest("Action 'run_xcode_command' requires file (a workspace-relative path).")
            }
        }
        if action.requiresConfirm, !confirm {
            throw ExtV2Error.invalidRequest("Action '\(action.rawValue)' requires confirm: true.")
        }
    }

    public static func run(
        action: UseExtensionAction, extensionId: String?, command: String?,
        file: String?, selection: UseExtensionSelection?, args: [String: Any],
        limit: Int, workspaceRoot: URL
    ) async throws -> UseExtensionOutcome {
        switch action {
        case .list: return try await runList(limit: limit)
        case .details: return try await runDetails(extensionId: extensionId!)
        case .listCommands: return try await runListCommands(extensionId: extensionId!)
        case .listXcodeCommands: return runListXcodeCommands()
        case .activate: return try await runActivate(extensionId: extensionId!, workspaceRoot: workspaceRoot)
        case .deactivate: return runDeactivate(extensionId: extensionId!)
        case .execute: return try await runExecute(
            extensionId: extensionId!, command: command!, args: args, workspaceRoot: workspaceRoot)
        case .runXcodeCommand: return try await runXcodeCommand(
            command: command!, file: file!, selection: selection, workspaceRoot: workspaceRoot)
        case .enable: return try runSetEnabled(extensionId: extensionId!, enabled: true)
        case .disable: return try runSetEnabled(extensionId: extensionId!, enabled: false)
        case .diagnostics: return runDiagnostics(extensionId: extensionId!, limit: limit)
        }
    }

    // MARK: Read-only actions

    private static func runList(limit: Int) async -> UseExtensionOutcome {
        let manager = ExtV2Manager.shared
        manager.refreshInstalled()
        // Row cap via subscript slice (not output truncation).
        let records = manager.installed.count > limit
            ? Array(manager.installed[..<limit])
            : manager.installed
        if records.isEmpty {
            return UseExtensionOutcome(
                output: "No extensions installed. Discover extensions from the Extensions sidebar (Open VSX registry) or register the sample native plugin.",
                data: ["action": "list", "count": "0"])
        }
        let lines = records.map { record in
            "\(record.id) — \(record.metadata.displayName) v\(record.metadata.version) [\(record.metadata.kind.displayName), \(record.state.displayName)]"
        }
        return UseExtensionOutcome(
            output: lines.joined(separator: "\n"),
            data: ["action": "list", "count": String(records.count)])
    }

    private static func runDetails(extensionId: String) async throws -> UseExtensionOutcome {
        let manager = ExtV2Manager.shared
        manager.refreshInstalled()
        guard let record = manager.installed.first(where: { $0.id == extensionId }) else {
            throw ExtV2Error.notInstalled(extensionId)
        }
        var lines: [String] = [
            "\(record.metadata.displayName) (\(record.id))",
            "Version: \(record.metadata.version)",
            "Kind: \(record.metadata.kind.displayName)",
            "State: \(record.state.displayName)",
            "Enabled: \(record.isEnabled)",
            "Description: \(record.metadata.description)",
        ]
        if !record.dependencies.isEmpty {
            let satisfied = record.dependencies.map { dep in
                let ok = manager.installed.contains { $0.id == dep && $0.isEnabled }
                return "\(dep) (\(ok ? "satisfied" : "missing"))"
            }
            lines.append("Dependencies: \(satisfied.joined(separator: ", "))")
        }
        let granted = manager.permissions.grantedCapabilities(for: extensionId)
        lines.append("Granted capabilities: \(granted.isEmpty ? "none" : granted.map(\.displayName).joined(separator: ", "))")
        if let lastError = record.lastError {
            lines.append("Last error: \(lastError)")
        }
        if record.metadata.kind == .vscode,
           let manifest = try? ExtV2ManifestParser.parseFile(
            at: URL(fileURLWithPath: record.installPath).appendingPathComponent("extension/package.json")) {
            let report = ExtV2Compatibility.evaluate(manifest: manifest)
            lines.append("Compatible: \(report.compatible)")
            if !report.reasons.isEmpty {
                lines.append("Compatibility notes: \(report.reasons.joined(separator: " "))")
            }
        }
        if let contribution = manager.contributions[extensionId], !contribution.commands.isEmpty {
            lines.append("Running commands: \(contribution.commands.map(\.command).joined(separator: ", "))")
        }
        return UseExtensionOutcome(
            output: lines.joined(separator: "\n"),
            data: ["action": "details", "extensionId": extensionId,
                   "state": record.state.rawValue, "kind": record.metadata.kind.rawValue])
    }

    private static func runListCommands(extensionId: String) async throws -> UseExtensionOutcome {
        let manager = ExtV2Manager.shared
        manager.refreshInstalled()
        guard let record = manager.installed.first(where: { $0.id == extensionId }) else {
            throw ExtV2Error.notInstalled(extensionId)
        }
        switch record.metadata.kind {
        case .vscode:
            if let contribution = manager.contributions[extensionId] {
                return commandsOutcome(extensionId: extensionId, commands: contribution.commands.map(\.command), note: "running")
            }
            if let manifest = try? ExtV2ManifestParser.parseFile(
                at: URL(fileURLWithPath: record.installPath).appendingPathComponent("extension/package.json")) {
                return commandsOutcome(
                    extensionId: extensionId,
                    commands: manifest.contributesCommands.map(\.command),
                    note: "not running; activate first to execute")
            }
            return UseExtensionOutcome(
                output: "No commands found for \(extensionId): the installed manifest could not be read.",
                data: ["action": "list_commands", "extensionId": extensionId, "count": "0"])
        case .native:
            let manifest = ExtV2NativePluginRegistry.shared.manifests.first { "swiftcode.\($0.id)" == extensionId }
            let commands = manifest?.commands.map(\.command) ?? []
            return commandsOutcome(extensionId: extensionId, commands: commands, note: "native plugin")
        case .xcodeCommand:
            return runListXcodeCommands()
        }
    }

    private static func commandsOutcome(extensionId: String, commands: [String], note: String) -> UseExtensionOutcome {
        if commands.isEmpty {
            return UseExtensionOutcome(
                output: "Extension \(extensionId) contributes no commands (\(note)).",
                data: ["action": "list_commands", "extensionId": extensionId, "count": "0"])
        }
        return UseExtensionOutcome(
            output: commands.joined(separator: "\n") + "\n(\(note))",
            data: ["action": "list_commands", "extensionId": extensionId, "count": String(commands.count)])
    }

    private static func runListXcodeCommands() -> UseExtensionOutcome {
        let identifiers = ExtV2XcodeCommandRegistry.shared.allIdentifiers
        if identifiers.isEmpty {
            return UseExtensionOutcome(
                output: "No Xcode-compatible commands are registered. Only registered source-editor command logic can run; XcodeKit binaries cannot run inside SwiftCode.",
                data: ["action": "list_xcode_commands", "count": "0"])
        }
        return UseExtensionOutcome(
            output: identifiers.joined(separator: "\n"),
            data: ["action": "list_xcode_commands", "count": String(identifiers.count)])
    }

    private static func runDiagnostics(extensionId: String, limit: Int) -> UseExtensionOutcome {
        let entries = Array(ExtV2DiagnosticsService.shared.entries(for: extensionId).suffix(limit))
        if entries.isEmpty {
            return UseExtensionOutcome(
                output: "No diagnostics recorded for \(extensionId).",
                data: ["action": "diagnostics", "extensionId": extensionId, "count": "0"])
        }
        let formatter = ISO8601DateFormatter()
        let lines = entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue)] \(entry.message)"
        }
        return UseExtensionOutcome(
            output: lines.joined(separator: "\n"),
            data: ["action": "diagnostics", "extensionId": extensionId, "count": String(entries.count)])
    }

    // MARK: Lifecycle and execution

    private static func runActivate(extensionId: String, workspaceRoot: URL) async throws -> UseExtensionOutcome {
        let manager = ExtV2Manager.shared
        manager.setWorkspaceRoot(workspaceRoot)
        let contribution = try await manager.activate(extensionId: extensionId)
        var lines = ["Activated \(extensionId)."]
        if !contribution.commands.isEmpty {
            lines.append("Commands: \(contribution.commands.map(\.command).joined(separator: ", "))")
        }
        if !contribution.outputLines.isEmpty {
            lines.append("Output: \(contribution.outputLines.joined(separator: " "))")
        }
        return UseExtensionOutcome(
            output: lines.joined(separator: "\n"),
            data: ["action": "activate", "extensionId": extensionId, "state": "running"])
    }

    private static func runDeactivate(extensionId: String) -> UseExtensionOutcome {
        ExtV2Manager.shared.deactivate(extensionId: extensionId)
        return UseExtensionOutcome(
            output: "Deactivated \(extensionId).",
            data: ["action": "deactivate", "extensionId": extensionId, "state": "stopped"])
    }

    private static func runExecute(
        extensionId: String, command: String, args: [String: Any], workspaceRoot: URL
    ) async throws -> UseExtensionOutcome {
        let manager = ExtV2Manager.shared
        manager.setWorkspaceRoot(workspaceRoot)
        manager.refreshInstalled()
        guard let record = manager.installed.first(where: { $0.id == extensionId }) else {
            throw ExtV2Error.notInstalled(extensionId)
        }
        guard record.isEnabled else { throw ExtV2Error.disabled(extensionId) }
        // With confirmation already given, a stopped VS Code host is
        // activated first so one call works end to end instead of
        // failing with "not running" and requiring a second call.
        if record.metadata.kind == .vscode, !manager.hostManager.isRunning(extensionId: extensionId) {
            _ = try await manager.activate(extensionId: extensionId)
        }
        // Arguments are passed as one JSON object argument so the
        // extension receives its named arguments intact.
        let hostArgs: [ExtV2JSONValue] = args.isEmpty ? [] : [.object(args.mapValues { anyToJSON($0) })]
        let result = try await manager.executeCommand(
            extensionId: extensionId, command: command, args: hostArgs)
        return UseExtensionOutcome(
            output: result.isEmpty ? "(command returned no output)" : result,
            data: ["action": "execute", "extensionId": extensionId, "command": command])
    }

    private static func runSetEnabled(extensionId: String, enabled: Bool) throws -> UseExtensionOutcome {
        let manager = ExtV2Manager.shared
        manager.refreshInstalled()
        guard manager.installed.contains(where: { $0.id == extensionId }) else {
            throw ExtV2Error.notInstalled(extensionId)
        }
        manager.setEnabled(extensionId: extensionId, enabled: enabled)
        let state = manager.installed.first(where: { $0.id == extensionId })?.state.displayName ?? "unknown"
        return UseExtensionOutcome(
            output: "\(enabled ? "Enabled" : "Disabled") \(extensionId) (state: \(state)).",
            data: ["action": enabled ? "enable" : "disable", "extensionId": extensionId, "state": state])
    }

    // MARK: Xcode command execution against a real file

    private static func runXcodeCommand(
        command: String, file: String, selection: UseExtensionSelection?, workspaceRoot: URL
    ) async throws -> UseExtensionOutcome {
        guard !file.hasPrefix("/") else {
            throw ExtV2Error.invalidRequest("File paths must be workspace-relative: \(file)")
        }
        let root = workspaceRoot.standardized
        let target = root.appendingPathComponent(file).standardized
        guard target == root || target.path.hasPrefix(root.path + "/") else {
            throw ExtV2Error.invalidRequest("File escapes the workspace: \(file)")
        }
        guard let commandObject = ExtV2XcodeCommandRegistry.shared.command(for: command) else {
            let available = ExtV2XcodeCommandRegistry.shared.allIdentifiers.joined(separator: ", ")
            throw ExtV2Error.invalidRequest("Unknown Xcode command '\(command)'. Registered commands: \(available.isEmpty ? "none" : available)")
        }
        let original: String
        do {
            original = try String(contentsOf: target, encoding: .utf8)
        } catch {
            throw ExtV2Error.invalidRequest("Could not read '\(file)': \(error.localizedDescription)")
        }
        let lines = original.components(separatedBy: "\n")
        let range: ExtV2SourceRange
        if let selection {
            guard selection.startLine < lines.count, selection.endLine < lines.count,
                  selection.startColumn <= lines[selection.startLine].count,
                  selection.endColumn <= lines[selection.endLine].count,
                  selection.startLine <= selection.endLine else {
                throw ExtV2Error.invalidRequest("Selection is outside the file.")
            }
            range = ExtV2SourceRange(
                start: ExtV2SourcePosition(line: selection.startLine, column: selection.startColumn),
                end: ExtV2SourcePosition(line: selection.endLine, column: selection.endColumn))
        } else {
            range = ExtV2SourceRange(
                start: ExtV2SourcePosition(line: 0, column: 0),
                end: ExtV2SourcePosition(line: max(lines.count - 1, 0), column: lines.last?.count ?? 0))
        }
        let buffer = ExtV2SourceTextBuffer(text: original, selections: [range])
        // A throwing command leaves the file untouched because the
        // write below only happens on success.
        try await commandObject.perform(
            invocation: ExtV2SourceEditorInvocation(buffer: buffer, commandIdentifier: command))
        let updated = buffer.completeBuffer
        guard updated != original else {
            return UseExtensionOutcome(
                output: "Command '\(command)' made no changes to \(file).",
                data: ["action": "run_xcode_command", "command": command, "file": file, "changed": "false"])
        }
        do {
            try updated.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            throw ExtV2Error.unknown("Command ran but the file could not be written: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(
            name: .ExtV2WorkspaceFileDidChange,
            object: nil,
            userInfo: ["path": file, "extensionId": "use_extension"])
        ExtV2DiagnosticsService.shared.info("Xcode command '\(command)' updated \(file).", extensionId: "use_extension")
        let summary = "Command '\(command)' updated \(file) (\(lines.count) lines before, \(updated.components(separatedBy: "\n").count) lines after).\nNew content:\n\(updated)"
        return UseExtensionOutcome(
            output: summary,
            data: ["action": "run_xcode_command", "command": command, "file": file, "changed": "true"],
            filesChanged: [file])
    }

    // MARK: Helpers

    private static func anyToJSON(_ value: Any) -> ExtV2JSONValue {
        if let string = value as? String { return .string(string) }
        if let bool = value as? Bool { return .bool(bool) }
        if let int = value as? Int { return .int(int) }
        if let double = value as? Double { return .double(double) }
        if let number = value as? NSNumber { return .double(number.doubleValue) }
        if let array = value as? [Any] { return .array(array.map(anyToJSON)) }
        if let dict = value as? [String: Any] { return .object(dict.mapValues(anyToJSON)) }
        return .string(String(describing: value))
    }
}
