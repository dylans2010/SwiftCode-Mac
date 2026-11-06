// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/FeatureFlags/FeatureFlagsView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
//
// Adaptation: Legacy bound this view to Legacy's `FeatureFlags.shared`
// (`SwiftCode/Backend/Developer/FeatureFlags.swift`). Production's
// equivalent is `DeveloperFeatureFlags` (swiftcode-ide/Developer/
// DeveloperFeatureFlags.swift), which deliberately omits Legacy's
// `bypass_paywall` flag — paywall bypasses are excluded from this
// migration by final decision — so the "Access Control" section has no
// toggle here. All other flags keep Legacy's names and UserDefaults
// behaviour through `DeveloperFeatureFlags`.
import SwiftUI
import SwiftCodeUI

struct FeatureFlagsView: View {
    @State private var flags = DeveloperFeatureFlags.shared

    var body: some View {
        Form {
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
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Feature Flags")
    }
}
