import SwiftUI

struct AppDetailsInfo: View {
    @Binding var appName: String
    @Binding var bundleIdentifier: String
    @Binding var marketingVersion: String
    @Binding var buildVersion: String
    @Binding var supportedDevices: String

    // Expanded metadata fields
    @State private var minDeploymentTarget = "16.0"
    @State private var appCategory = "Developer Tools"
    @State private var cameraPrivacyDescription = "Required to capture photos for profile customization."
    @State private var locationPrivacyDescription = "Required to show proximity locations of projects."
    @State private var sandboxEnabled = true
    @State private var outgoingNetworkEnabled = true
    @State private var targetPlatform = "macOS / iOS"
    @State private var activeBuildConfiguration = "Debug"

    @State private var validationWarning: String? = nil

    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Core App Metadata") {
                    TextField("App Display Name", text: $appName)

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Bundle Identifier", text: $bundleIdentifier)
                            .autocorrectionDisabled()
                        if let warning = validationWarning {
                            Text(warning)
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                    .onChange(of: bundleIdentifier) { _, newValue in
                        validateBundleID(newValue)
                    }

                    HStack {
                        TextField("App Version", text: $marketingVersion)
                        TextField("Build Number", text: $buildVersion)
                    }
                }

                Section("Target & Deployment Platform") {
                    Picker("Devices", selection: $supportedDevices) {
                        Text("iPhone").tag("iPhone")
                        Text("iPad").tag("iPad")
                        Text("iPhone + iPad").tag("iPhone + iPad")
                    }
                    .pickerStyle(.segmented)

                    Picker("Minimum OS Target", selection: $minDeploymentTarget) {
                        Text("iOS 15.0").tag("15.0")
                        Text("iOS 16.0").tag("16.0")
                        Text("iOS 17.0").tag("17.0")
                        Text("macOS 14.0").tag("14.0")
                    }

                    Picker("App Category", selection: $appCategory) {
                        Text("Developer Tools").tag("Developer Tools")
                        Text("Utilities").tag("Utilities")
                        Text("Productivity").tag("Productivity")
                        Text("Education").tag("Education")
                    }
                }

                Section("Privacy Usage Descriptions") {
                    TextField("Camera Description", text: $cameraPrivacyDescription)
                    TextField("Location Description", text: $locationPrivacyDescription)
                }

                Section("Entitlements Summary") {
                    Toggle("App Sandbox", isOn: $sandboxEnabled)
                    Toggle("Outgoing Network (Client)", isOn: $outgoingNetworkEnabled)
                }

                Section("Read-Only Project Info") {
                    LabeledContent("Target Platform", value: targetPlatform)
                    LabeledContent("Active Configuration", value: activeBuildConfiguration)
                    LabeledContent("Target Membership", value: "Primary App Target")
                    LabeledContent("Localizations", value: "en (Development)")
                }

                Section {
                    Button("Reset to Defaults") {
                        revertToDefaults()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("App Details Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onSkip() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply & Build") {
                        onContinue()
                    }
                    .fontWeight(.semibold)
                    .disabled(validationWarning != nil)
                }
            }
        }
    }

    private func validateBundleID(_ value: String) {
        let pattern = "^[a-zA-Z0-9.-]+$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: value.utf16.count)
        if regex?.firstMatch(in: value, options: [], range: range) == nil {
            validationWarning = "Invalid characters in Bundle Identifier (alphanumeric, dot, dash only)."
        } else {
            validationWarning = nil
        }
    }

    private func revertToDefaults() {
        appName = "My App"
        bundleIdentifier = "com.example.myapp"
        marketingVersion = "1.0"
        buildVersion = "1"
        supportedDevices = "iPhone + iPad"
        minDeploymentTarget = "16.0"
        appCategory = "Developer Tools"
        cameraPrivacyDescription = "Required to capture photos for profile customization."
        locationPrivacyDescription = "Required to show proximity locations of projects."
        sandboxEnabled = true
        outgoingNetworkEnabled = true
        validationWarning = nil
    }
}
