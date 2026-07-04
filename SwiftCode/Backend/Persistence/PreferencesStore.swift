import Foundation

public actor PreferencesStore {
    public static let shared = PreferencesStore()

    public func set(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    public func get(forKey key: String) -> Any? {
        return UserDefaults.standard.object(forKey: key)
    }
}
