// LANDED PORT — `OpenCodeConfiguration.load()` / `save()`, missing API on the
// destination type (Dylan's own SwiftCode code, MIT-authorised direct port).
// Legacy source: `SwiftCode/Backend/Assist/AssistProviderConfiguration.swift`
// (Legacy main ab03f681) — `OpenCodeConfiguration.load()` / `save()` only.
// The struct itself is already on main
// (`SwiftCodeAssistant/Models/AssistModelRouting.swift`); this file only adds the
// two missing members as an extension, so there is no duplicate declaration.
//
// Destination: SwiftCodeAssistant/Providers/OpenCodeConfiguration+Load.swift.
//
// Storage deviation (deliberate, follows the destination's design): Legacy
// read/wrote three UserDefaults keys (`opencode.serverURL`,
// `opencode.agentName`, `opencode.managedServerEnabled`). The destination
// persists provider configuration in its settings store
// (`AssistantSettings`, JSON under the `SwiftCode.codingAssistant`
// UserDefaults key — see `Preferences.codingAssistant` in SwiftCodeIDECore).
// `load()` / `save()` therefore read/write that same blob through
// `OpenCodeConfiguration(settings:)` / `apply(to:)`, using the exact key
// and decode path `Preferences.codingAssistant` uses, so there is no
// second source of truth and no Legacy-era key is consulted. A user with
// only Legacy-era keys gets the destination defaults.
// `managedServerEnabled` has no field in `AssistantSettings`: `load()`
// always returns `false` for it (matching `init(settings:)`) and `save()`
// does not persist it — same behaviour as the destination struct today.
// Callers unblocked: `OpenCodeClient` (7 call sites), `OpenCodeSDKProvider`
// (default parameter), `AssistSettingsView` (`openCodeServerURL` /
// `openCodeAgentName` state + `saveOpenCodeConfiguration()`).

import Foundation

extension OpenCodeConfiguration {
    /// Reads the persisted configuration from SwiftCode's settings store
    /// (`AssistantSettings` under `SwiftCode.codingAssistant`). Returns the
    /// destination defaults when nothing is stored yet.
    public static func load() -> OpenCodeConfiguration {
        OpenCodeConfiguration(settings: loadSettings())
    }

    /// Writes the configuration back into SwiftCode's settings store
    /// (read-modify-write of the `AssistantSettings` blob, so unrelated
    /// settings are preserved).
    public func save() {
        var settings = Self.loadSettings()
        apply(to: &settings)
        Self.storeSettings(settings)
    }

    private static func loadSettings() -> AssistantSettings {
        guard let data = UserDefaults.standard.data(forKey: "SwiftCode.codingAssistant"),
              let settings = try? JSONDecoder().decode(AssistantSettings.self, from: data) else {
            return AssistantSettings()
        }
        return settings
    }

    private static func storeSettings(_ settings: AssistantSettings) {
        UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: "SwiftCode.codingAssistant")
    }
}
