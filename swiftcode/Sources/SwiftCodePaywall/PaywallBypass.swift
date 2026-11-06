import Foundation

/// The developer `bypass_paywall` flag, ported from Legacy's
/// `FeatureFlags` (`SwiftCode/Backend/Developer/FeatureFlags.swift`).
///
/// Same UserDefaults key (`"bypass_paywall"`) as Legacy, so a flag
/// set in the Legacy build carries over. The flag is developer-only:
/// no paywall UI toggles it (Legacy's toggle lived in its separate
/// `FeatureFlagsView`, which is not part of this slice), and it never
/// creates an entitlement — it only makes
/// `PaywallEntitlementState.isPro` report `true` while it is on.
/// `PaywallStore.refreshBypassFlag()` re-reads it after it changes.
public struct PaywallBypass {
    /// The UserDefaults key, identical to Legacy's.
    public static let defaultsKey = "bypass_paywall"

    private let defaults: UserDefaults

    /// - Parameter defaults: the defaults to read/write. Defaults to
    ///   `.standard`; tests pass an isolated suite.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}
