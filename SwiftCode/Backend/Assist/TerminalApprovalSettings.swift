import Combine
import Foundation

/// Preset terminal command definition for common developer workflows.
public struct TerminalPresetCommand: Identifiable, Hashable, Sendable {
    public var id: String { command }
    public let command: String
    public let category: String
    public let description: String

    public init(command: String, category: String, description: String) {
        self.command = command
        self.category = category
        self.description = description
    }
}

/// User-controlled policy for the `use_terminal` tool's approval prompt.
///
/// - `fullAccess`: when on, Assist may run ANY terminal command without
///   asking, in every session, until the user turns it off.
/// - `allowedCommands`: commands that always run without a prompt unless the
///   user removes them from the list.
///
/// Both are persisted in UserDefaults. Defaults are conservative: full access
/// off, allow-list empty (every command prompts).
@MainActor
public final class TerminalApprovalSettings: ObservableObject {
    public static let shared = TerminalApprovalSettings()

    /// Curated preset list of 60 common developer terminal commands across categories.
    public static let presetCommands: [TerminalPresetCommand] = [
        // Git
        TerminalPresetCommand(command: "git status", category: "Git", description: "Show working tree status"),
        TerminalPresetCommand(command: "git diff", category: "Git", description: "Show changes between commits or working tree"),
        TerminalPresetCommand(command: "git log", category: "Git", description: "Show commit logs"),
        TerminalPresetCommand(command: "git branch", category: "Git", description: "List or manage branches"),
        TerminalPresetCommand(command: "git checkout", category: "Git", description: "Switch branches or restore working tree files"),
        TerminalPresetCommand(command: "git switch", category: "Git", description: "Switch branches"),
        TerminalPresetCommand(command: "git add", category: "Git", description: "Add file contents to the index"),
        TerminalPresetCommand(command: "git commit", category: "Git", description: "Record changes to the repository"),
        TerminalPresetCommand(command: "git push", category: "Git", description: "Update remote refs along with associated objects"),
        TerminalPresetCommand(command: "git pull", category: "Git", description: "Fetch from and integrate with another repository or branch"),
        TerminalPresetCommand(command: "git fetch", category: "Git", description: "Download objects and refs from another repository"),
        TerminalPresetCommand(command: "git merge", category: "Git", description: "Join two or more development histories together"),
        TerminalPresetCommand(command: "git rebase", category: "Git", description: "Reapply commits on top of another base tip"),
        TerminalPresetCommand(command: "git stash", category: "Git", description: "Stash the changes in a dirty working directory away"),
        TerminalPresetCommand(command: "git reset", category: "Git", description: "Reset current HEAD to the specified state"),
        TerminalPresetCommand(command: "git clone", category: "Git", description: "Clone a repository into a new directory"),
        TerminalPresetCommand(command: "git remote", category: "Git", description: "Manage set of tracked repositories"),
        TerminalPresetCommand(command: "git restore", category: "Git", description: "Restore working tree files"),

        // Swift & Xcode
        TerminalPresetCommand(command: "swift build", category: "Swift & Xcode", description: "Build Swift package target"),
        TerminalPresetCommand(command: "swift test", category: "Swift & Xcode", description: "Run Swift package tests"),
        TerminalPresetCommand(command: "swift run", category: "Swift & Xcode", description: "Build and run a Swift executable"),
        TerminalPresetCommand(command: "swift package", category: "Swift & Xcode", description: "Perform Swift package operations"),
        TerminalPresetCommand(command: "xcodebuild", category: "Swift & Xcode", description: "Build Xcode projects and workspaces"),
        TerminalPresetCommand(command: "xcrun", category: "Swift & Xcode", description: "Run Xcode developer tools and utilities"),
        TerminalPresetCommand(command: "xcodegen", category: "Swift & Xcode", description: "Generate Xcode project from project.yml spec"),
        TerminalPresetCommand(command: "pod", category: "Swift & Xcode", description: "CocoaPods dependency manager"),
        TerminalPresetCommand(command: "carthage", category: "Swift & Xcode", description: "Carthage dependency manager"),

        // Package Managers
        TerminalPresetCommand(command: "brew", category: "Package Managers", description: "Homebrew macOS package manager"),
        TerminalPresetCommand(command: "npm", category: "Package Managers", description: "Node package manager"),
        TerminalPresetCommand(command: "npx", category: "Package Managers", description: "Execute npm package binaries directly"),
        TerminalPresetCommand(command: "yarn", category: "Package Managers", description: "Yarn package manager"),
        TerminalPresetCommand(command: "pnpm", category: "Package Managers", description: "Fast, disk space efficient package manager"),
        TerminalPresetCommand(command: "bun", category: "Package Managers", description: "All-in-one JavaScript runtime & package manager"),

        // System & Files
        TerminalPresetCommand(command: "ls", category: "System & Files", description: "List directory contents"),
        TerminalPresetCommand(command: "pwd", category: "System & Files", description: "Print current working directory"),
        TerminalPresetCommand(command: "cd", category: "System & Files", description: "Change working directory"),
        TerminalPresetCommand(command: "mkdir", category: "System & Files", description: "Create directories"),
        TerminalPresetCommand(command: "cp", category: "System & Files", description: "Copy files and directories"),
        TerminalPresetCommand(command: "mv", category: "System & Files", description: "Move or rename files and directories"),
        TerminalPresetCommand(command: "rm", category: "System & Files", description: "Remove files or directories"),
        TerminalPresetCommand(command: "cat", category: "System & Files", description: "Concatenate and print file contents"),
        TerminalPresetCommand(command: "find", category: "System & Files", description: "Search for files in directory hierarchy"),
        TerminalPresetCommand(command: "grep", category: "System & Files", description: "Print lines matching pattern"),
        TerminalPresetCommand(command: "chmod", category: "System & Files", description: "Change file mode bits / permissions"),
        TerminalPresetCommand(command: "touch", category: "System & Files", description: "Change file timestamps or create empty file"),
        TerminalPresetCommand(command: "open", category: "System & Files", description: "Open file, folder, or URL in default application"),

        // Utilities & Network
        TerminalPresetCommand(command: "curl", category: "Utilities & Network", description: "Transfer data from or to a server"),
        TerminalPresetCommand(command: "echo", category: "Utilities & Network", description: "Display line of text / environment output"),
        TerminalPresetCommand(command: "which", category: "Utilities & Network", description: "Locate command executable path in PATH"),
        TerminalPresetCommand(command: "env", category: "Utilities & Network", description: "Print active environment variables"),

        // Runtimes & Containers
        TerminalPresetCommand(command: "python3", category: "Runtimes & Containers", description: "Python 3 interpreter"),
        TerminalPresetCommand(command: "pip3", category: "Runtimes & Containers", description: "Python 3 package installer"),
        TerminalPresetCommand(command: "pip", category: "Runtimes & Containers", description: "Python package manager"),
        TerminalPresetCommand(command: "ruby", category: "Runtimes & Containers", description: "Ruby language interpreter"),
        TerminalPresetCommand(command: "gem", category: "Runtimes & Containers", description: "RubyGem package manager"),
        TerminalPresetCommand(command: "bundle", category: "Runtimes & Containers", description: "Ruby Bundler dependency manager"),
        TerminalPresetCommand(command: "cargo", category: "Runtimes & Containers", description: "Rust package manager and build tool"),
        TerminalPresetCommand(command: "go", category: "Runtimes & Containers", description: "Go language toolchain"),
        TerminalPresetCommand(command: "docker", category: "Runtimes & Containers", description: "Docker container engine"),
        TerminalPresetCommand(command: "docker-compose", category: "Runtimes & Containers", description: "Define and run multi-container Docker apps")
    ]

    private let fullAccessKey = "assist_terminal_full_access"
    private let allowedCommandsKey = "assist_terminal_allowed_commands"

    @Published public var fullAccess: Bool {
        didSet { UserDefaults.standard.set(fullAccess, forKey: fullAccessKey) }
    }

    @Published public var allowedCommands: [String] {
        didSet { persistCommands() }
    }

    private init() {
        self.fullAccess = UserDefaults.standard.bool(forKey: fullAccessKey)
        if let data = UserDefaults.standard.data(forKey: allowedCommandsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.allowedCommands = decoded
        } else {
            // Migrate from any legacy comma-separated string value.
            let legacy = UserDefaults.standard.string(forKey: allowedCommandsKey) ?? ""
            self.allowedCommands = legacy
                .components(separatedBy: ",")
                .map { Self.normalize($0) }
                .filter { !$0.isEmpty }
        }
    }

    // MARK: - Mutation

    /// Adds a command to the allow-list. Returns false when empty/duplicate.
    @discardableResult
    public func addCommand(_ command: String) -> Bool {
        let normalized = Self.normalize(command)
        guard !normalized.isEmpty, !allowedCommands.contains(normalized) else { return false }
        allowedCommands.append(normalized)
        return true
    }

    /// Bulk adds commands to the allow-list.
    public func addAllCommands(_ commands: [String]) {
        var updated = allowedCommands
        for command in commands {
            let normalized = Self.normalize(command)
            if !normalized.isEmpty && !updated.contains(normalized) {
                updated.append(normalized)
            }
        }
        allowedCommands = updated
    }

    /// Adds all predefined preset commands to the allow-list.
    public func addAllPresets() {
        let presetList = Self.presetCommands.map { $0.command }
        addAllCommands(presetList)
    }

    public func removeCommand(_ command: String) {
        let normalized = Self.normalize(command)
        allowedCommands.removeAll { $0 == normalized || $0 == command }
    }

    /// Removes all commands from the allow-list.
    public func removeAllCommands() {
        allowedCommands.removeAll()
    }

    public func moveCommand(from source: IndexSet, to destination: Int) {
        var updated = allowedCommands
        let items = source.sorted().map { updated[$0] }
        for index in source.sorted(by: >) { updated.remove(at: index) }
        var insertAt = destination
        for index in source where index < destination { insertAt -= 1 }
        updated.insert(contentsOf: items, at: max(0, min(insertAt, updated.count)))
        allowedCommands = updated
    }

    // MARK: - Policy query

    /// Whether `command` may run without a user approval prompt.
    public func isApprovalBypassed(for command: String) -> Bool {
        if fullAccess { return true }
        return isAllowed(command: command)
    }

    /// Whether `command` matches the allow-list.
    ///
    /// Matching rules (documented in the settings UI):
    /// - A single-word entry (e.g. `git`) allows any command whose first
    ///   whitespace-separated token equals the entry.
    /// - A multi-word entry (e.g. `git status`) must match the whole command
    ///   exactly after whitespace normalization.
    public func isAllowed(command: String) -> Bool {
        let normalized = Self.normalize(command)
        guard !normalized.isEmpty else { return false }
        let firstToken = normalized.components(separatedBy: .whitespaces).first ?? ""
        return allowedCommands.contains { entry in
            if entry.contains(" ") {
                return entry == normalized
            } else {
                return entry == firstToken
            }
        }
    }

    // MARK: - Private

    private func persistCommands() {
        if let data = try? JSONEncoder().encode(allowedCommands) {
            UserDefaults.standard.set(data, forKey: allowedCommandsKey)
        }
    }

    static func normalize(_ command: String) -> String {
        command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
