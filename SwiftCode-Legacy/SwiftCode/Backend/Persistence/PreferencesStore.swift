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
