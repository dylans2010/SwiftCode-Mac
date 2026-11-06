// Ported from Legacy `SwiftCode/Models/AppSettings.swift` (commit d51a8f0d, Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources/SwiftCodeAssistant.
//
// `reverseEnabled` is the one AppSettings flag the Reverse subsystem reads.
// There is no `AppSettings` type anywhere in the destination
// (swiftcode/Sources has only comment mentions of it, plus the unrelated
// `AssistantSettings` struct), so the flag lives here as a real,
// UserDefaults-backed setting — not a stub — reading the exact key and
// default Legacy's AppSettings owned:
//
//   key:     "assist.reverseEnabled"
//   default: true  (Legacy `AppSettings.init`: `UserDefaults.standard.object(forKey: "assist.reverseEnabled") as? Bool ?? true`)
//   writes:  `UserDefaults.standard.set(_:forKey:)` (Legacy's `didSet` did the
//            same, alongside its debounced-save bookkeeping)
//
// `ReverseManager` reads `ReverseSettings.reverseEnabled`. When a destination
// `AppSettings` (or an Assist settings store) lands, move this flag there
// and re-point the manager; the UserDefaults key must stay
// `assist.reverseEnabled` so existing user settings keep working.

import Foundation

/// The Reverse subsystem's enabled flag, backed by UserDefaults.
public enum ReverseSettings {
    /// Gates the whole Reverse subsystem. Default true, matching Legacy.
    public static var reverseEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "assist.reverseEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "assist.reverseEnabled") }
    }
}
