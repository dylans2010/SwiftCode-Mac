import Foundation

public actor SDKCommandRegistry {

    public static let shared = SDKCommandRegistry()

    private static let maxCommandsPerExtension = 64
    private static let commandIDPattern = #"^[a-z][a-z0-9-]{0,63}$"#
    private static let maxTitleLength = 128

    private var commandsByExtension: [String: [String: SDKCommandDefinition]] = [:]

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

    public func unregister(commandID: String, extensionID: String) {
        guard var owned = commandsByExtension[extensionID] else { return }
        owned.removeValue(forKey: commandID)
        if owned.isEmpty {
            commandsByExtension.removeValue(forKey: extensionID)
        } else {
            commandsByExtension[extensionID] = owned
        }
    }

    public func unregisterAll(extensionID: String) {
        commandsByExtension.removeValue(forKey: extensionID)
    }

    public func commands(for extensionID: String) -> [SDKCommandDefinition] {
        (commandsByExtension[extensionID] ?? [:]).values.sorted { $0.id < $1.id }
    }

    public func allCommands() -> [(extensionID: String, command: SDKCommandDefinition)] {
        commandsByExtension.flatMap { (extensionID, owned) in
            owned.values.map { (extensionID: extensionID, command: $0) }
        }
        .sorted {
            if $0.extensionID != $1.extensionID { return $0.extensionID < $1.extensionID }
            return $0.command.id < $1.command.id
        }
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }
}
