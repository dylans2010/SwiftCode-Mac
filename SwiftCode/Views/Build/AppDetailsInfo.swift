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
                    // Core App Metadata Card
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
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("App Display Name", text: $appName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Bundle Identifier")
                                    .font(.caption.bold())
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

                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("App Version")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("App Version", text: $marketingVersion)
                                        .textFieldStyle(.roundedBorder)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Build Number")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    TextField("Build Number", text: $buildVersion)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Target & Deployment Platform Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Target & Deployment Platform", systemImage: "square.grid.2x2.fill")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Devices")
                                    .font(.caption.bold())
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
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Picker("Minimum OS Target", selection: $minDeploymentTarget) {
                                        Text("iOS 15.0").tag("15.0")
                                        Text("iOS 16.0").tag("16.0")
                                        Text("iOS 17.0").tag("17.0")
                                        Text("macOS 14.0").tag("14.0")
                                    }
                                    .pickerStyle(.menu)
                                }

                                Spacer()

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("App Category")
                                        .font(.caption.bold())
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

                    // Privacy Usage Descriptions Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Privacy Usage Descriptions", systemImage: "hand.raised.fill")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Camera Description")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("Camera Description", text: $cameraPrivacyDescription)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Location Description")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("Location Description", text: $locationPrivacyDescription)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Entitlements Summary Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Entitlements Summary", systemImage: "lock.shield.fill")
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

                    // Read-Only Project Info Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Read-Only Project Info", systemImage: "folder.fill")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()
                            }

                            HStack {
                                Text("Target Platform").font(.subheadline)
                                Spacer()
                                Text(targetPlatform).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Active Configuration").font(.subheadline)
                                Spacer()
                                Text(activeBuildConfiguration).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Localizations").font(.subheadline)
                                Spacer()
                                Text("en (Development)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Reset Button
                    Button(action: revertToDefaults) {
                        Label("Reset App Details to Defaults", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundColor(.red)
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
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
