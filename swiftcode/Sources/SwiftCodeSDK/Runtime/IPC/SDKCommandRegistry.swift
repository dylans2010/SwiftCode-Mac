// Ported from Legacy `SwiftCode/SDK/Host/PublicAPI/SDKCommandRegistry.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: SDKCommandRegistry.

import Foundation

public actor SDKCommandRegistry {

    public static let shared = SDKCommandRegistry()

    // MARK: - Limits (spec §6.2, §10.6; aligned with manifest §7.3 caps)

    /// Maximum registered commands per extension (spec §10.6).
    private static let maxCommandsPerExtension = 64
    /// Command-ID shape, identical to the manifest contribution rule.
    private static let commandIDPattern = #"^[a-z][a-z0-9-]{0,63}$"#
    /// Maximum human-readable title length.
    private static let maxTitleLength = 128

    // MARK: - State

    /// extensionID -> (commandID -> definition).
    private var commandsByExtension: [String: [String: SDKCommandDefinition]] = [:]

    // MARK: - Registration

    /// Registers a command contributed by an extension.
    ///
    /// Validation (every rejection is an `SDKError`):
    /// - `extensionID` must be non-empty → `.invalidArgument`.
    /// - `id` must match `^[a-z][a-z0-9-]{0,63}$` → `.invalidArgument`.
    /// - `title` must be 1–128 characters after trimming whitespace →
    ///   `.invalidArgument`.
    /// - Registering an already-registered ID *for the same extension* is
    ///   rejected → `.invalidArgument` ("already registered"). Use
    ///   `unregister` first to replace a command.
    /// - More than 64 commands for one extension →
    ///   `.resourceLimitExceeded`.
    ///
    /// Cross-extension duplicates are allowed (documented above).
    public func register(_ command: SDKCommandDefinition, extensionID: String) throws {
        let owner = extensionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !owner.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "Command registration requires a non-empty extension ID.",
                suggestion: "Pass the activating extension's manifest ID.",
                diagnostics: ["commandID": command.id]
            )
        }

        guard Self.matches(command.id, pattern: Self.commandIDPattern) else {
            throw SDKError(
                code: .invalidArgument,
                message: "Command ID \"\(command.id)\" is invalid.",
                suggestion: "Use a lowercase kebab-case ID, e.g. \"my-command-2\" (1–64 characters).",
                diagnostics: ["extensionID": owner]
            )
        }

        let title = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw SDKError(
                code: .invalidArgument,
                message: "Command \"\(command.id)\" has a blank title.",
                suggestion: "Provide a human-readable \"title\" for the command.",
                diagnostics: ["extensionID": owner]
            )
        }
        guard title.count <= Self.maxTitleLength else {
            throw SDKError(
                code: .invalidArgument,
                message: "Command \"\(command.id)\" has a title longer than \(Self.maxTitleLength) characters.",
                suggestion: "Shorten the command title to \(Self.maxTitleLength) characters or fewer.",
                diagnostics: ["extensionID": owner]
            )
        }

        var owned = commandsByExtension[owner, default: [:]]
        if owned[command.id] != nil {
            throw SDKError(
                code: .invalidArgument,
                message: "Command \"\(command.id)\" is already registered by this extension.",
                suggestion: "Unregister the command first if you intend to replace it.",
                diagnostics: ["extensionID": owner]
            )
        }
        guard owned.count < Self.maxCommandsPerExtension else {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "Extension \"\(owner)\" already has \(Self.maxCommandsPerExtension) registered commands.",
                suggestion: "Unregister unused commands before registering more.",
                diagnostics: ["extensionID": owner]
            )
        }

        owned[command.id] = SDKCommandDefinition(id: command.id, title: title)
        commandsByExtension[owner] = owned
    }

    // MARK: - Removal

    /// Unregisters one command.
    ///
    /// Removes the command **only if it is owned by `extensionID`**.
    /// An extension can never remove another extension's commands — a
    /// foreign (`extensionID`, `commandID`) pair is a silent no-op.
    public func unregister(commandID: String, extensionID: String) {
        guard var owned = commandsByExtension[extensionID] else { return }
        owned.removeValue(forKey: commandID)
        if owned.isEmpty {
            commandsByExtension.removeValue(forKey: extensionID)
        } else {
            commandsByExtension[extensionID] = owned
        }
    }

    /// Removes every command owned by `extensionID`.
    ///
    /// Called by the extension lifecycle on deactivation (spec §10.5:
    /// "Deactivation disposes commands, event subscriptions, build handles,
    /// and other extension-owned resources") and on runtime crash / forced
    /// termination, so a dead extension leaves no stale commands.
    public func unregisterAll(extensionID: String) {
        commandsByExtension.removeValue(forKey: extensionID)
    }

    // MARK: - Queries

    /// All commands owned by one extension, sorted by ID (stable for UI).
    public func commands(for extensionID: String) -> [SDKCommandDefinition] {
        (commandsByExtension[extensionID] ?? [:]).values.sorted { $0.id < $1.id }
    }

    /// Every registered command across all extensions, sorted by extension
    /// ID then command ID. Intended for future Studio/palette UI; the IPC
    /// dispatcher also uses this to answer command-listing requests.
    public func allCommands() -> [(extensionID: String, command: SDKCommandDefinition)] {
        commandsByExtension.flatMap { (extensionID, owned) in
            owned.values.map { (extensionID: extensionID, command: $0) }
        }
        .sorted {
            if $0.extensionID != $1.extensionID { return $0.extensionID < $1.extensionID }
            return $0.command.id < $1.command.id
        }
    }

    // MARK: - Validation helper

    /// Compiled per call (not stored in a static) to stay clean under
    /// Swift 6 strict concurrency — same convention as `SDKManifestValidator`.
    private static func matches(_ value: String, pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }
}
