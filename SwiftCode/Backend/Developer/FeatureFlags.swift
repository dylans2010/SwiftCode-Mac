import Foundation

final class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()

    @Published var bypass_paywall: Bool {
        didSet {
            UserDefaults.standard.set(bypass_paywall, forKey: "bypass_paywall")
            EntitlementManager.shared.updateProStatus(isPro: EntitlementManager.shared.isProUser)
        }
    }

    @Published var verbose_logging: Bool {
        didSet { UserDefaults.standard.set(verbose_logging, forKey: "verbose_logging") }
    }

    @Published var simulate_api_failures: Bool {
        didSet { UserDefaults.standard.set(simulate_api_failures, forKey: "simulate_api_failures") }
    }

    @Published var simulate_deployment_errors: Bool {
        didSet { UserDefaults.standard.set(simulate_deployment_errors, forKey: "simulate_deployment_errors") }
    }

    @Published var disable_network_cache: Bool {
        didSet { UserDefaults.standard.set(disable_network_cache, forKey: "disable_network_cache") }
    }

    @Published var enable_internal_metrics: Bool {
        didSet { UserDefaults.standard.set(enable_internal_metrics, forKey: "enable_internal_metrics") }
    }

    @Published var force_ai_debug_mode: Bool {
        didSet { UserDefaults.standard.set(force_ai_debug_mode, forKey: "force_ai_debug_mode") }
    }

    @Published var enable_debug_overlays: Bool {
        didSet { UserDefaults.standard.set(enable_debug_overlays, forKey: "enable_debug_overlays") }
    }

    private init() {
        self.bypass_paywall = UserDefaults.standard.bool(forKey: "bypass_paywall")
        self.verbose_logging = UserDefaults.standard.bool(forKey: "verbose_logging")
        self.simulate_api_failures = UserDefaults.standard.bool(forKey: "simulate_api_failures")
        self.simulate_deployment_errors = UserDefaults.standard.bool(forKey: "simulate_deployment_errors")
        self.disable_network_cache = UserDefaults.standard.bool(forKey: "disable_network_cache")
        self.enable_internal_metrics = UserDefaults.standard.bool(forKey: "enable_internal_metrics")
        self.force_ai_debug_mode = UserDefaults.standard.bool(forKey: "force_ai_debug_mode")
        self.enable_debug_overlays = UserDefaults.standard.bool(forKey: "enable_debug_overlays")
    }
}
