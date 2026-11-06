import Foundation

// MARK: - Meta slash-command host effects (Wave 17, Slice A)
//
// Ported from Legacy (Dylan's own code; direct port authorised
// under MIT):
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MetaSlashCommandManager.swift`
//     — `executeCommand`'s side effects: `AppSettings.shared.metaReasoningEffort`,
//     `AppSettings.shared.metaAssistModelID`, `AssistManager.shared.clearChat()`,
//     `MetaAccountAuthService.shared.startAuthFlow()`.
//   * `SwiftCode/Backend/Assist/AssistManager.swift` — `clearChat()`
//     (cancel the active tasks, then clear the transcript).
//   * `SwiftCode/Backend/Assist/Assist Frameworks/Meta/MuseCodeCLIHelper.swift`
//     — `MetaAccountAuthService.startAuthFlow()` / `runLoginFlow`
//     (run `muse login`, capture the `auth.meta.com` URL from its
//     output, open it in the browser).
//
// What is deliberately different from Legacy — read this before
// assuming a behaviour carried over:
//   * The applier is pure: it takes settings in and returns the
//     updated settings plus what the host must do. It touches no
//     singleton, no `Preferences`, no executor. The host
//     (`CodingAssistantModel`) writes the settings back, stops
//     the running turn, resets the executor session, and posts
//     the result text into the conversation.
//   * `/effort` is validated against the known tiers (Legacy set
//     whatever string it was given). An unknown tier changes
//     nothing and the message lists the valid tiers, so a typo
//     never silently arms a bad value for `turn/start`.
//   * `/model` records the model verbatim (Legacy: `metaAssistModelID`
//     was used as-is by the provider, empty meaning the default).
//     The Wave 15 router's rule applies — the selected id is never
//     silently replaced by another model (`AssistModelRouter.resolveDefaultModel`
//     synthesizes from the preferred id when it is undiscovered).
//     When the id is not in the known Meta catalog the message says
//     so plainly: the next turn sends it as-is and the Muse host
//     reports it if it does not exist. The host also switches the
//     live session (`MetaAssistTurnExecutor.switchModel`) so a
//     running session does not keep the old model.
//   * `/clear` clears the executor session and starts a fresh
//     conversation. The old conversation stays in the library
//     (SwiftCode never deletes a transcript implicitly); Legacy's
//     `clearChat` dropped the transcript, which has no SwiftCode
//     equivalent.
//   * `/login` has NO interactive flow in SwiftCode. Legacy ran
//     `muse login` and opened the auth URL in the browser; SwiftCode
//     never launches an interactive login (see
//     `MuseCodeMSPBridge.swift`: `MuseCodeCLIHelper` is not
//     ported, and a turn without credentials fails with a
//     sign-in hint). The effect therefore surfaces the honest
//     instruction — run `muse` once in Terminal and sign in
//     there — and never pretends a login flow started. The host
//     refines the message to "already signed in" when a
//     credential file exists.

/// What the host must do for one applied slash-command effect,
/// plus the settings the effect produced.
public struct MetaSlashCommandEffectOutcome: Sendable, Equatable {
    /// The settings after the effect (unchanged when the effect
    /// writes nothing).
    public var settings: AssistantSettings
    /// The text shown to the user (Legacy `executeCommand`'s
    /// return string, or the honest instruction / refusal).
    public var message: String
    /// The host must stop the running turn, reset the Meta
    /// executor session, and start a fresh conversation.
    public var clearsSession: Bool

    public init(settings: AssistantSettings, message: String, clearsSession: Bool = false) {
        self.settings = settings
        self.message = message
        self.clearsSession = clearsSession
    }
}

/// Applies a `MetaSlashCommandEffect` to settings (pure).
public enum MetaSlashCommandEffectApplier {
    /// The reasoning-effort tiers `/effort` accepts (the
    /// built-in command's own choices, Legacy verbatim).
    public static let validReasoningEfforts: [String] = [
        "none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra",
    ]

    /// What `/login` tells the user. SwiftCode has no interactive
    /// login flow: the only real path is signing in through the
    /// `muse` CLI once, in Terminal.
    public static let loginInstruction =
        "Assist with Meta signs in outside SwiftCode: run `muse` once in Terminal and sign in there, then try again. " +
        "SwiftCode never launches an interactive `muse login` and cannot sign you in by itself."

    /// Applies one effect. `knownModelIDs` is the Meta catalog
    /// the host knows (the fallback catalog plus the live
    /// availability list); it only decides whether the `/model`
    /// message carries the unknown-model caveat — the model is
    /// recorded verbatim either way.
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
            // The host never routes `.insertText` through the
            // applier: it leaves the text in the input (see
            // `CodingAssistantModel.handleMetaSlashCommand`).
            return MetaSlashCommandEffectOutcome(settings: settings, message: "")
        }
    }
}
