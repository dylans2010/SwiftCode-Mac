import Foundation

// MARK: - Meta slash commands (Wave 16, Slice B)
//
// Ported from Legacy (Dylan's own code; direct port authorised
// under MIT):
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaSlashCommandManager.swift`
//     — the built-in `/` command catalog, `muse skills list`
//     capture, search, and the execution dispatcher.
//
// What is deliberately different from Legacy:
//   * No `ObservableObject` / `@Published` / Combine / SwiftUI:
//     this is a plain `Sendable` struct. The host owns one and
//     replaces it when a capture merges new skills in.
//   * `executeCommand` does NOT touch `AppSettings`,
//     `AssistManager`, or `MetaAccountAuthService`. It returns
//     the text to send plus a `MetaSlashCommandEffect` the host
//     applies (set the reasoning effort / model in settings,
//     clear the session, start the Meta login flow, or insert the
//     command text into the input). Legacy's side effects are
//     therefore preserved as data, not re-implemented against
//     singletons that do not exist in Ycode.
//   * The terminal capture runs `muse skills list` through a
//     plain `Process` with Legacy's 15-second timeout (Legacy's
//     own `runProcess` accepted a timeout but never enforced it;
//     here it is enforced by terminating the child). The TSV
//     parsing is the pure `parseSkillsList(_:)` function, so
//     tests feed sample output without launching anything.
//   * Faithful quirk kept: the built-in `/model` choices list
//     `muse-swift-2.0`, which is not in the fallback model
//     catalog (`MetaAssistProvider.fallbackModels`). Legacy
//     shipped the same mismatch; the choice is the user's to
//     make and the bridge reports an unknown model honestly.

/// One argument a slash command takes (Legacy `MetaCommandArgument`).
public enum MetaCommandArgument: Identifiable, Hashable, Sendable {
    case options(name: String, choices: [String], defaultValue: String?)
    case text(name: String, placeholder: String, isOptional: Bool)

    public var id: String {
        switch self {
        case .options(let name, _, _): return "opt-\(name)"
        case .text(let name, _, _): return "txt-\(name)"
        }
    }

    public var argumentName: String {
        switch self {
        case .options(let name, _, _): return name
        case .text(let name, _, _): return name
        }
    }
}

/// One Meta slash command (Legacy `MetaSlashCommand`).
public struct MetaSlashCommand: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let title: String
    public let description: String
    public let syntax: String
    /// SF Symbol name (Legacy's `icon`).
    public let icon: String
    public let category: String
    public let arguments: [MetaCommandArgument]
    public let isTerminalSkill: Bool

    public var requiresArguments: Bool { !arguments.isEmpty }

    public init(
        id: String,
        name: String,
        title: String,
        description: String,
        syntax: String,
        icon: String = "terminal.fill",
        category: String = "General",
        arguments: [MetaCommandArgument] = [],
        isTerminalSkill: Bool = false
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.description = description
        self.syntax = syntax
        self.icon = icon
        self.category = category
        self.arguments = arguments
        self.isTerminalSkill = isTerminalSkill
    }
}

/// What the host must do for a slash command (Legacy's
/// `executeCommand` side effects, as data).
public enum MetaSlashCommandEffect: Sendable, Equatable {
    /// Set the Meta reasoning effort (Legacy: `AppSettings.shared.metaReasoningEffort`).
    case setReasoningEffort(String)
    /// Switch the Meta model (Legacy: `AppSettings.shared.metaAssistModelID`).
    case setModel(String)
    /// Clear the Assist session (Legacy: `AssistManager.shared.clearChat()`).
    case clearSession
    /// Start the Meta authentication flow (Legacy: `MetaAccountAuthService.shared.startAuthFlow()`).
    case startLogin
    /// Put this text into the input (or send it): the command has
    /// no host-side effect.
    case insertText(String)
}

/// Discovers, caches, parses, and manages Meta slash commands
/// (Legacy `MetaSlashCommandManager`, minus the singletons).
public struct MetaSlashCommandManager: Sendable {
    /// Capture timeout for `muse skills list` (Legacy: 15 seconds).
    public static let skillsListTimeout: TimeInterval = 15

    public private(set) var commands: [MetaSlashCommand]
    public private(set) var isCapturing: Bool = false
    public private(set) var lastCapturedAt: Date?

    public init(commands: [MetaSlashCommand] = Self.builtInCommands) {
        self.commands = commands
    }

    // MARK: - Built-in commands (Legacy `loadBuiltInCommands`, verbatim)

    public static let builtInCommands: [MetaSlashCommand] = [
        MetaSlashCommand(id: "effort", name: "/effort", title: "Effort Level",
                         description: "Set the model's reasoning effort level",
                         syntax: "/effort [<none|minimal|low|medium|high|xhigh|max|ultra>]",
                         icon: "gauge.with.needle", category: "Model",
                         arguments: [.options(name: "Effort Tier",
                                              choices: ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"],
                                              defaultValue: "high")]),
        MetaSlashCommand(id: "model", name: "/model", title: "Choose Model",
                         description: "Select active Meta Assist model",
                         syntax: "/model [<model-id>]",
                         icon: "cpu", category: "Model",
                         arguments: [.options(name: "Model",
                                              choices: ["muse-wonder-1.0", "muse-spark-1.3", "muse-swift-2.0"],
                                              defaultValue: "muse-wonder-1.0")]),
        MetaSlashCommand(id: "skills", name: "/skills", title: "Skills Manager",
                         description: "Browse, reload, manage, and use skills",
                         syntax: "/skills [import|reload|manage|diagnostics|use <id> [prompt]]",
                         icon: "wand.and.stars", category: "Skills",
                         arguments: [.options(name: "Action",
                                              choices: ["list", "reload", "manage", "diagnostics", "import"],
                                              defaultValue: "list")]),
        MetaSlashCommand(id: "deep-research", name: "/deep-research", title: "Deep Research",
                         description: "Research a question across sources with cross-checking and citations",
                         syntax: "/deep-research <question>",
                         icon: "magnifyingglass.circle.fill", category: "Research",
                         arguments: [.text(name: "Question",
                                           placeholder: "Enter research topic or question...",
                                           isOptional: false)]),
        MetaSlashCommand(id: "goal", name: "/goal", title: "Autonomous Goal",
                         description: "Start or manage continuous work toward a goal",
                         syntax: "/goal [<objective>|edit <objective>|clear|cancel|stop|pause|resume]",
                         icon: "target", category: "Agent",
                         arguments: [.options(name: "Goal Action",
                                              choices: ["status", "resume", "pause", "stop", "cancel", "clear", "edit"],
                                              defaultValue: "status")]),
        MetaSlashCommand(id: "rules", name: "/rules", title: "Governing Rules",
                         description: "Show which markdown rule files govern this session",
                         syntax: "/rules [import]",
                         icon: "doc.text.badge.plus", category: "System",
                         arguments: [.options(name: "Action",
                                              choices: ["show", "import"],
                                              defaultValue: "show")]),
        MetaSlashCommand(id: "export", name: "/export", title: "Export Session",
                         description: "Save the conversation or the full session trajectory log",
                         syntax: "/export [transcript|trajectory]",
                         icon: "square.and.arrow.up", category: "Session",
                         arguments: [.options(name: "Format",
                                              choices: ["transcript", "trajectory"],
                                              defaultValue: "transcript")]),
        MetaSlashCommand(id: "voice", name: "/voice", title: "Voice Input",
                         description: "Manage voice input transcription and audio diagnostics",
                         syntax: "/voice [status|debug]",
                         icon: "waveform", category: "System",
                         arguments: [.options(name: "Option",
                                              choices: ["status", "debug"],
                                              defaultValue: "status")]),
        MetaSlashCommand(id: "stop", name: "/stop", title: "Stop Tasks",
                         description: "Stop background tasks and terminal commands",
                         syntax: "/stop [all]",
                         icon: "stop.circle.fill", category: "Agent",
                         arguments: [.options(name: "Scope",
                                              choices: ["all"],
                                              defaultValue: "all")]),
        MetaSlashCommand(id: "copy", name: "/copy", title: "Copy to Clipboard",
                         description: "Copy a response, code block, or ran command to clipboard",
                         syntax: "/copy [N]",
                         icon: "doc.on.doc", category: "Session",
                         arguments: [.options(name: "Target",
                                              choices: ["last", "1", "2", "3"],
                                              defaultValue: "last")]),
        MetaSlashCommand(id: "name", name: "/name", title: "Name Session",
                         description: "Name or rename this session for resume and reference",
                         syntax: "/name [<name>]",
                         icon: "tag", category: "Session",
                         arguments: [.text(name: "Session Name",
                                           placeholder: "e.g. feature-auth-refactor",
                                           isOptional: false)]),
        MetaSlashCommand(id: "resume", name: "/resume", title: "Resume Session",
                         description: "Resume an earlier Muse Code session",
                         syntax: "/resume [--last|<id-or-name>]",
                         icon: "arrow.clockwise", category: "Session",
                         arguments: [.options(name: "Target",
                                              choices: ["--last"],
                                              defaultValue: "--last")]),
        MetaSlashCommand(id: "fork", name: "/fork", title: "Fork Conversation",
                         description: "Branch this session from the latest message",
                         syntax: "/fork [prompt]",
                         icon: "arrow.triangle.branch", category: "Session",
                         arguments: [.text(name: "Prompt",
                                           placeholder: "Branch goal or prompt...",
                                           isOptional: true)]),
        MetaSlashCommand(id: "feedback", name: "/feedback", title: "Send Feedback",
                         description: "Send quick feedback or report a bug to the team",
                         syntax: "/feedback [note]",
                         icon: "envelope", category: "System",
                         arguments: [.text(name: "Note",
                                           placeholder: "Feedback message or bug report...",
                                           isOptional: false)]),
        MetaSlashCommand(id: "clear", name: "/clear", title: "Clear Session",
                         description: "Clear terminal and start a fresh session",
                         syntax: "/clear",
                         icon: "trash", category: "Session"),
        MetaSlashCommand(id: "rewind", name: "/rewind", title: "Rewind",
                         description: "Rewind conversation to an earlier input",
                         syntax: "/rewind",
                         icon: "arrow.uturn.backward", category: "Session"),
        MetaSlashCommand(id: "side", name: "/side", title: "Side Chat",
                         description: "Start a side conversation without polluting main context",
                         syntax: "/side",
                         icon: "bubble.left.and.bubble.right", category: "Session"),
        MetaSlashCommand(id: "init", name: "/init", title: "Initialize Workspace",
                         description: "Explore the workspace and create or improve AGENTS.md",
                         syntax: "/init",
                         icon: "sparkles", category: "Agent"),
        MetaSlashCommand(id: "subagents", name: "/subagents", title: "View Subagents",
                         description: "View running and past subagents in this workspace",
                         syntax: "/subagents",
                         icon: "person.3", category: "Agent"),
        MetaSlashCommand(id: "settings", name: "/settings", title: "Meta Settings",
                         description: "Open local Meta Code configuration and settings",
                         syntax: "/settings",
                         icon: "gearshape", category: "Configuration"),
        MetaSlashCommand(id: "keymap", name: "/keymap", title: "Keyboard Shortcuts",
                         description: "Show keyboard shortcuts and key bindings",
                         syntax: "/keymap",
                         icon: "keyboard", category: "Configuration"),
        MetaSlashCommand(id: "help", name: "/help", title: "Meta Help",
                         description: "Show Meta Code help and command catalog",
                         syntax: "/help",
                         icon: "questionmark.circle.fill", category: "General"),
        MetaSlashCommand(id: "theme", name: "/theme", title: "Theme",
                         description: "Choose color theme for Meta Code",
                         syntax: "/theme",
                         icon: "paintpalette", category: "Configuration"),
        MetaSlashCommand(id: "compact", name: "/compact", title: "Compact Context",
                         description: "Summarize conversation to free up context window",
                         syntax: "/compact",
                         icon: "arrow.down.right.and.arrow.up.left", category: "Session"),
        MetaSlashCommand(id: "recap", name: "/recap", title: "Recap Activity",
                         description: "Show a recap of recent session activity",
                         syntax: "/recap",
                         icon: "newspaper", category: "Session"),
        MetaSlashCommand(id: "plugins", name: "/plugins", title: "Plugins",
                         description: "Validate and manage installed plugins",
                         syntax: "/plugins",
                         icon: "puzzlepiece", category: "Skills"),
        MetaSlashCommand(id: "mcp", name: "/mcp", title: "MCP Servers",
                         description: "Show Model Context Protocol servers and active tools",
                         syntax: "/mcp",
                         icon: "network", category: "System"),
        MetaSlashCommand(id: "status", name: "/status", title: "Session Status",
                         description: "Show current session status and environment health",
                         syntax: "/status",
                         icon: "info.circle", category: "Session"),
        MetaSlashCommand(id: "usage", name: "/usage", title: "Usage & Cost",
                         description: "Show session usage, token count, and cost metrics",
                         syntax: "/usage",
                         icon: "chart.bar", category: "Session"),
        MetaSlashCommand(id: "permissions", name: "/permissions", title: "Permissions",
                         description: "Choose what Muse Code is allowed to execute and read",
                         syntax: "/permissions",
                         icon: "lock.shield", category: "Configuration"),
        MetaSlashCommand(id: "tasks", name: "/tasks", title: "Background Tasks",
                         description: "View and manage background tasks and active terminals",
                         syntax: "/tasks",
                         icon: "list.bullet.rectangle", category: "Agent"),
        MetaSlashCommand(id: "workflows", name: "/workflows", title: "Workflows",
                         description: "Browse workflow runs and multi-step plans",
                         syntax: "/workflows",
                         icon: "flowchart", category: "Agent"),
        MetaSlashCommand(id: "questions", name: "/questions", title: "Pending Questions",
                         description: "Answer pending questions from running agents",
                         syntax: "/questions",
                         icon: "questionmark.circle", category: "Session"),
        MetaSlashCommand(id: "hud", name: "/hud", title: "Status Bar HUD",
                         description: "Choose what appears in the bottom status bar",
                         syntax: "/hud",
                         icon: "menubar.dock.rectangle", category: "Configuration"),
        MetaSlashCommand(id: "login", name: "/login", title: "Log In",
                         description: "Log in with Meta account or using an API key",
                         syntax: "/login",
                         icon: "person.crop.circle.badge.plus", category: "System"),
        MetaSlashCommand(id: "logout", name: "/logout", title: "Log Out",
                         description: "Log out, forget saved login, and exit",
                         syntax: "/logout",
                         icon: "arrow.backward.circle", category: "System"),
    ]

    // MARK: - Dynamic terminal command capture

    /// Parses `muse skills list` TSV output into terminal-skill
    /// commands (Legacy `captureCommandsFromTerminal`, pure half).
    /// A line needs at least a name and one more tab field; `#`
    /// lines and blank names are skipped; the description comes
    /// from the fifth field, else the fourth, else
    /// `"Execute <name> skill"`. The title is the skill name with
    /// `-`/`_` as spaces, capitalized.
    public static func parseSkillsList(_ stdout: String) -> [MetaSlashCommand] {
        var skills: [MetaSlashCommand] = []
        for line in stdout.components(separatedBy: .newlines) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { continue }
            let skillName = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !skillName.isEmpty, !skillName.hasPrefix("#") else { continue }

            var description = "Execute \(skillName) skill"
            if parts.count >= 5 {
                let fullDesc = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
                if !fullDesc.isEmpty { description = fullDesc }
            } else if parts.count >= 4 {
                let fullDesc = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
                if !fullDesc.isEmpty { description = fullDesc }
            }

            let formattedTitle = skillName
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized

            skills.append(MetaSlashCommand(
                id: "skill-\(skillName)",
                name: "/\(skillName)",
                title: formattedTitle,
                description: description,
                syntax: "/\(skillName) [prompt]",
                icon: "bolt.badge.automatic.fill",
                category: "Meta Skills",
                arguments: [.text(name: "Instructions",
                                  placeholder: "Optional instructions for \(formattedTitle)...",
                                  isOptional: true)],
                isTerminalSkill: true
            ))
        }
        return skills
    }

    /// Merges freshly captured terminal skills into the catalog:
    /// previously captured skills are replaced, built-ins kept.
    /// Returns true when anything was merged (Legacy set
    /// `lastCapturedAt` only then).
    public mutating func mergeCapturedSkills(_ skills: [MetaSlashCommand]) -> Bool {
        guard !skills.isEmpty else { return false }
        var merged = commands.filter { !$0.isTerminalSkill }
        merged.append(contentsOf: skills)
        commands = merged
        lastCapturedAt = Date()
        return true
    }

    /// Captures skills live from the `muse` binary (`muse skills
    /// list`) and merges them. A missing binary, a non-zero exit,
    /// or a timeout leaves the built-ins untouched, exactly as
    /// Legacy silently fell back to them. The runner is injectable
    /// so tests can feed canned output without a binary.
    public mutating func captureCommandsFromTerminal(
        executable: URL?,
        timeoutSeconds: TimeInterval = Self.skillsListTimeout,
        runner: (@Sendable (URL) async throws -> String)? = nil
    ) async {
        guard !isCapturing else { return }
        guard let executable else { return }
        isCapturing = true
        defer { isCapturing = false }
        let stdout: String
        do {
            if let runner {
                stdout = try await runner(executable)
            } else {
                stdout = try await Self.runSkillsList(executable: executable, timeoutSeconds: timeoutSeconds)
            }
        } catch {
            return // Silently fall back to built-in commands.
        }
        guard !stdout.isEmpty else { return }
        _ = mergeCapturedSkills(Self.parseSkillsList(stdout))
    }

    /// Runs `muse skills list` and returns its stdout. Times out
    /// after `timeoutSeconds` by terminating the child.
    static func runSkillsList(executable: URL, timeoutSeconds: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await Task.detached {
                    let process = Process()
                    process.executableURL = executable
                    process.arguments = ["skills", "list"]
                    let out = Pipe()
                    process.standardOutput = out
                    process.standardError = FileHandle.nullDevice
                    process.standardInput = FileHandle.nullDevice
                    try process.run()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        throw MuseCodeCLIError.executionFailed(
                            exitCode: process.terminationStatus,
                            stderr: "muse skills list failed.")
                    }
                    return String(decoding: data, as: UTF8.self)
                }.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw MuseCodeCLIError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - Search & filtering

    /// Filters the catalog by name, title, description, or
    /// category (Legacy `searchCommands`). A leading `/` on the
    /// query is ignored; an empty query returns everything.
    public func searchCommands(query: String) -> [MetaSlashCommand] {
        let trimmed = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return commands }
        let cleanQuery = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        return commands.filter { cmd in
            let cmdNameClean = cmd.name.hasPrefix("/") ? String(cmd.name.dropFirst()).lowercased() : cmd.name.lowercased()
            return cmdNameClean.contains(cleanQuery) ||
                cmd.title.lowercased().contains(cleanQuery) ||
                cmd.description.lowercased().contains(cleanQuery) ||
                cmd.category.lowercased().contains(cleanQuery)
        }
    }

    // MARK: - Execution dispatcher

    /// Executes a slash command with its UI-provided argument
    /// (Legacy `executeCommand`). Returns the text to show/send
    /// and the host-side effect, if any. Legacy's wording is kept
    /// verbatim for the four effect commands.
    public func executeCommand(_ command: MetaSlashCommand, argument: String?) -> (text: String, effect: MetaSlashCommandEffect?) {
        let argString = (argument ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch command.id {
        case "effort":
            if !argString.isEmpty {
                return ("Meta reasoning effort set to '\(argString)'.", .setReasoningEffort(argString))
            }
        case "model":
            if !argString.isEmpty {
                return ("Meta Assist model switched to '\(argString)'.", .setModel(argString))
            }
        case "clear":
            return ("Cleared Assist session.", .clearSession)
        case "login":
            return ("Starting Meta authentication flow...", .startLogin)
        default:
            break
        }

        // Default: the full command string, to place in the input
        // or send as-is.
        if argString.isEmpty {
            return (command.name, .insertText(command.name))
        }
        return ("\(command.name) \(argString)", .insertText("\(command.name) \(argString)"))
    }
}
