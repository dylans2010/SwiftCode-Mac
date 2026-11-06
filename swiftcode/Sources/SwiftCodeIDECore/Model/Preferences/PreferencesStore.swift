// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Persistence/PreferencesStore.swift
//   (Legacy main ab03f681) — verbatim, no adaptations.
//   Staged by migration subagent F2 (unowned-dependency triage) — NOT yet
//   landed in the repo.
//
// Destination: SwiftCodeIDECore/Model/PreferencesStore.swift.
//
// Home chosen: `SwiftCodeIDECore` — all 12 live main call sites are there
// (`SettingsViewModel`: `selected_ai_model`, `custom_ai_endpoint`,
// `custom_ai_headers`, `use_custom_ai`, `user_name`,
// `file_header_template`). Foundation-only actor over UserDefaults.

import Foundation

public actor PreferencesStore {
    public static let shared = PreferencesStore()

    public func set(_ value: any Sendable, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    public func get(forKey key: String) -> (any Sendable)? {
        let value = UserDefaults.standard.object(forKey: key)

        switch value {
        case let v as String: return v
        case let v as Int: return v
        case let v as Double: return v
        case let v as Float: return v
        case let v as Bool: return v
        case let v as Data: return v
        case let v as Date: return v
        case let v as URL: return v
        case let v as [String]: return v
        case let v as [Int]: return v
        case let v as [Double]: return v
        case let v as [Bool]: return v
        case let v as [String: String]: return v
        default: return nil
        }
    }
}
