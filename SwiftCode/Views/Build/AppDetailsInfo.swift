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
            ScrollView {
                VStack(spacing: 24) {

                    // Card 1: Core App Metadata
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Core App Metadata", systemImage: "info.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("App Display Name")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("App Display Name", text: $appName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Bundle Identifier")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Bundle Identifier", text: $bundleIdentifier)
                                    .textFieldStyle(.roundedBorder)
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

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("App Version")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("App Version", text: $marketingVersion)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Build Number")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    TextField("Build Number", text: $buildVersion)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 2: Target & Deployment Platform
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Target & Deployment Platform", systemImage: "macbook.and.iphone")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Supported Devices")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Picker("Devices", selection: $supportedDevices) {
                                    Text("iPhone").tag("iPhone")
                                    Text("iPad").tag("iPad")
                                    Text("iPhone + iPad").tag("iPhone + iPad")
                                }
                                .pickerStyle(.segmented)
                            }

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Minimum OS Target")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Minimum OS Target", selection: $minDeploymentTarget) {
                                        Text("iOS 15.0").tag("15.0")
                                        Text("iOS 16.0").tag("16.0")
                                        Text("iOS 17.0").tag("17.0")
                                        Text("macOS 14.0").tag("14.0")
                                    }
                                    .pickerStyle(.menu)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("App Category")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("App Category", selection: $appCategory) {
                                        Text("Developer Tools").tag("Developer Tools")
                                        Text("Utilities").tag("Utilities")
                                        Text("Productivity").tag("Productivity")
                                        Text("Education").tag("Education")
                                    }
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 3: Privacy Usage Descriptions
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Privacy Usage Descriptions", systemImage: "hand.raised.fill")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Camera Description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Camera Description", text: $cameraPrivacyDescription)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Location Description")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Location Description", text: $locationPrivacyDescription)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 4: Entitlements Summary
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Entitlements Summary", systemImage: "shield.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            Toggle("App Sandbox", isOn: $sandboxEnabled)
                            Toggle("Outgoing Network (Client)", isOn: $outgoingNetworkEnabled)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Card 5: Read-Only Project Info
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Read-Only Project Info", systemImage: "lock.fill")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()
                            }

                            HStack {
                                Text("Target Platform")
                                Spacer()
                                Text(targetPlatform).bold().foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Active Configuration")
                                Spacer()
                                Text(activeBuildConfiguration).bold().foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Target Membership")
                                Spacer()
                                Text("Primary App Target").bold().foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Localizations")
                                Spacer()
                                Text("en (Development)").bold().foregroundColor(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Actions Card
                    GroupBox {
                        HStack {
                            Spacer()
                            Button("Reset to Defaults", role: .destructive) {
                                revertToDefaults()
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                }
                .padding(24)
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
