import SwiftUI
import YcodeUI

struct FeatureFlagsView: View {
    @State private var flags = DeveloperFeatureFlags.shared

    var body: some View {
        Form {
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
