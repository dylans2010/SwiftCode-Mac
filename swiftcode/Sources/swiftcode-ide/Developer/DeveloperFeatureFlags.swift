import Foundation

/// Developer feature flags for the ported developer views.
///
/// Legacy's `FeatureFlags` was a Legacy-only shared object. This is the
/// SwiftCode-side equivalent: a `UserDefaults`-backed flag set read by the
/// ported Feature Flags and Verbose Logging views.
///
/// Deliberately NOT ported: Legacy's `bypass_paywall` flag. Paywall
/// bypasses are excluded from this migration by final decision, so no
/// flag here can disable the paywall.
@Observable
@MainActor
final class DeveloperFeatureFlags {
    static let shared = DeveloperFeatureFlags()

    private static func key(_ name: String) -> String { "swiftcode.developer.\(name)" }

    var simulate_api_failures: Bool = UserDefaults.standard.bool(forKey: key("simulate_api_failures")) {
        didSet { UserDefaults.standard.set(simulate_api_failures, forKey: Self.key("simulate_api_failures")) }
    }
    var simulate_deployment_errors: Bool = UserDefaults.standard.bool(forKey: key("simulate_deployment_errors")) {
        didSet { UserDefaults.standard.set(simulate_deployment_errors, forKey: Self.key("simulate_deployment_errors")) }
    }
    var disable_network_cache: Bool = UserDefaults.standard.bool(forKey: key("disable_network_cache")) {
        didSet { UserDefaults.standard.set(disable_network_cache, forKey: Self.key("disable_network_cache")) }
    }
    var enable_internal_metrics: Bool = UserDefaults.standard.bool(forKey: key("enable_internal_metrics")) {
        didSet { UserDefaults.standard.set(enable_internal_metrics, forKey: Self.key("enable_internal_metrics")) }
    }
    var force_ai_debug_mode: Bool = UserDefaults.standard.bool(forKey: key("force_ai_debug_mode")) {
        didSet { UserDefaults.standard.set(force_ai_debug_mode, forKey: Self.key("force_ai_debug_mode")) }
    }
    var enable_debug_overlays: Bool = UserDefaults.standard.bool(forKey: key("enable_debug_overlays")) {
        didSet { UserDefaults.standard.set(enable_debug_overlays, forKey: Self.key("enable_debug_overlays")) }
    }
    var verbose_logging: Bool = UserDefaults.standard.bool(forKey: key("verbose_logging")) {
        didSet { UserDefaults.standard.set(verbose_logging, forKey: Self.key("verbose_logging")) }
    }
}
