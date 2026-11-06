import Foundation
import Observation

/// The master developer-mode toggle (ported from Legacy's
/// `DeveloperModeManager`).
///
/// Legacy's class was `ObservableObject` with `@Published`; this is the
/// same UserDefaults-backed flag (`developer_mode_enabled`) as an
/// `@Observable` type. It is the on/off switch for the developer tooling
/// surfaced by `DebugToolsRegistry`; the individual toggles live in
/// `DeveloperFeatureFlags` (`ycode/Sources/ycode-ide/Developer/`),
/// which another worker already ported.
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
