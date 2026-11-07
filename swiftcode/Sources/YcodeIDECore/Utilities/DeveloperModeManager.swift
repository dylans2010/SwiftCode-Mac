import Foundation
import Observation

@Observable
@MainActor
public final class DeveloperModeManager {
    public static let shared = DeveloperModeManager()

    public var isDeveloperModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDeveloperModeEnabled, forKey: Self.defaultsKey)
        }
    }

    public static let defaultsKey = "developer_mode_enabled"

    public init() {
        self.isDeveloperModeEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    public func enableDeveloperMode() {
        isDeveloperModeEnabled = true
    }

    public func disableDeveloperMode() {
        isDeveloperModeEnabled = false
    }
}
