import Combine
import Foundation

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

    public func removeCommand(_ command: String) {
        allowedCommands.removeAll { $0 == command }
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
