import SwiftUI

struct FeatureFlagsView: View {
    @StateObject private var flags = FeatureFlags.shared

    var body: some View {
        Form {
            Section("Access Control") {
                Toggle("Bypass Paywall", isOn: $flags.bypass_paywall)
            }
            Section("Simulation") {
                Toggle("Simulate API Failures", isOn: $flags.simulate_api_failures)
                Toggle("Simulate Deployment Errors", isOn: $flags.simulate_deployment_errors)
            }
            Section("Performance") {
                Toggle("Disable Network Cache", isOn: $flags.disable_network_cache)
                Toggle("Enable Internal Metrics", isOn: $flags.enable_internal_metrics)
            }
            Section("AI") {
                Toggle("Force AI Debug Mode", isOn: $flags.force_ai_debug_mode)
            }
            Section("UI") {
                Toggle("Enable Debug Overlays", isOn: $flags.enable_debug_overlays)
            }
        }
        .navigationTitle("Feature Flags")
    }
}
