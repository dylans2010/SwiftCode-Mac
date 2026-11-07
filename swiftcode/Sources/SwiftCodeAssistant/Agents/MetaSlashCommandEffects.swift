import Foundation

public struct MetaSlashCommandEffectOutcome: Sendable, Equatable {
    public var settings: AssistantSettings
    public var message: String
    public var clearsSession: Bool

    public init(settings: AssistantSettings, message: String, clearsSession: Bool = false) {
        self.settings = settings
        self.message = message
        self.clearsSession = clearsSession
    }
}

public enum MetaSlashCommandEffectApplier {
    public static let validReasoningEfforts: [String] = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra",
    ]

    public static let loginInstruction =
        "Assist with Meta signs in outside SwiftCode: run `muse` once in Terminal and sign in there, then try again. " +
        "SwiftCode never launches an interactive `muse login` and cannot sign you in by itself."

    public static func apply(
        _ effect: MetaSlashCommandEffect,
        settings: AssistantSettings,
        knownModelIDs: Set<String> = []
    ) -> MetaSlashCommandEffectOutcome {
        switch effect {
        case .setReasoningEffort(let raw):
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard validReasoningEfforts.contains(value) else {
                return MetaSlashCommandEffectOutcome(
                    settings: settings,
                    message: "Unknown reasoning effort '\(raw)'. Valid levels: \(validReasoningEfforts.joined(separator: ", ")).")
            }
            var updated = settings
            updated.metaReasoningEffort = value
            return MetaSlashCommandEffectOutcome(
                settings: updated,
                message: "Meta reasoning effort set to '\(value)'.")
        case .setModel(let raw):
            let modelID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            var updated = settings
            updated.setModel(modelID, for: .metaAssist)
            if knownModelIDs.contains(modelID) {
                return MetaSlashCommandEffectOutcome(
                    settings: updated,
                    message: "Meta Assist model switched to '\(modelID)'.")
            }
            return MetaSlashCommandEffectOutcome(
                settings: updated,
                message: "Meta Assist model switched to '\(modelID)'. That model is not in the known Meta catalog, " +
                    "so the next turn sends it as-is and the Muse host will report it if it does not exist.")
        case .clearSession:
            return MetaSlashCommandEffectOutcome(settings: settings, message: "Cleared Assist session.", clearsSession: true)
        case .startLogin:
            return MetaSlashCommandEffectOutcome(settings: settings, message: loginInstruction)
        case .insertText:
            return MetaSlashCommandEffectOutcome(settings: settings, message: "")
        }
    }
}
