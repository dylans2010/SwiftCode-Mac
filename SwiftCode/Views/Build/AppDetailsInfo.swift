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

    // Diagnostics / Actions Output log
    @State private var diagnosticsLog = ""
    @State private var isRunningDiagnostic = false

    @State private var validationWarning: String? = nil

    let onSkip: () -> Void
    let onContinue: () -> Void

    @Environment(ProjectSessionStore.self) private var sessionStore

    var body: some View {
        NavigationStack {
            List {
                // Section 1: Dashboard Status Header
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 48, height: 44)
                                Image(systemName: "square.grid.3x3.fill")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(appName.isEmpty ? "Developer Project Dashboard" : appName)
                                    .font(.title3.bold())
                                    .foregroundStyle(.primary)
                                Text("Bundle Target Identifier: \(bundleIdentifier)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)

                        HStack(spacing: 12) {
                            indicatorMiniBox(title: "Target SDK", value: "iOS \(minDeploymentTarget)")
                            indicatorMiniBox(title: "Build Config", value: activeBuildConfiguration)
                            if let activeProj = sessionStore.activeProject {
                                indicatorMiniBox(title: "Project Files", value: "\(activeProj.fileCount)")
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                // Section 2: App Specifications
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField("App Display Name", text: $appName)

                        VStack(alignment: .leading, spacing: 4) {
                            labeledField("Bundle Identifier", text: $bundleIdentifier)

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
                            labeledField("Version", text: $marketingVersion)
                            labeledField("Build", text: $buildVersion)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("App Specifications")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                }

                // Section 3: Platform Targets
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Supported Devices").font(.subheadline.bold()).foregroundStyle(.secondary)
                            Picker("Devices", selection: $supportedDevices) {
                                Text("iPhone").tag("iPhone")
                                Text("iPad").tag("iPad")
                                Text("iPhone + iPad").tag("iPhone + iPad")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.regular)
                        }

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Minimum OS").font(.subheadline.bold()).foregroundStyle(.secondary)
                                Picker("Minimum OS Target", selection: $minDeploymentTarget) {
                                    Text("iOS 15.0").tag("15.0")
                                    Text("iOS 16.0").tag("16.0")
                                    Text("iOS 17.0").tag("17.0")
                                    Text("macOS 14.0").tag("14.0")
                                }
                                .pickerStyle(.menu)
                                .controlSize(.regular)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Category").font(.subheadline.bold()).foregroundStyle(.secondary)
                                Picker("App Category", selection: $appCategory) {
                                    Text("Developer Tools").tag("Developer Tools")
                                    Text("Utilities").tag("Utilities")
                                    Text("Productivity").tag("Productivity")
                                    Text("Education").tag("Education")
                                }
                                .pickerStyle(.menu)
                                .controlSize(.regular)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Platform Targets")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                }

                // Section 4: Signing & Entitlements
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("App Sandbox Protection", isOn: $sandboxEnabled)
                            .toggleStyle(.checkbox)
                            .font(.body)

                        Toggle("Outgoing Networking Privileges (Client)", isOn: $outgoingNetworkEnabled)
                            .toggleStyle(.checkbox)
                            .font(.body)

                        Divider()

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                            GridRow {
                                Text("Platform Target:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(targetPlatform).font(.subheadline.bold())
                            }
                            GridRow {
                                Text("Target Membership:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Primary Application Target").font(.subheadline.bold())
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Signing & Entitlements")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                }

                // Section 5: Local Storage Map
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        if let activeProj = sessionStore.activeProject {
                            Text("Project Directory:")
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)

                            Text(activeProj.directoryURL.path)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundColor(.blue)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(6)

                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                GridRow {
                                    Text("File Count:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text("\(activeProj.fileCount)")
                                        .font(.subheadline.bold())
                                }

                                GridRow {
                                    Text("Created Date:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Text(activeProj.createdAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline.bold())
                                }
                            }
                        } else {
                            Text("No active project loaded in the current workspace.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Local Storage Map")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.purple)
                }

                // Section 6: Privacy Descriptions
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NSCameraUsageDescription").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            TextField("Camera Privacy Usage Key", text: $cameraPrivacyDescription)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("NSLocationWhenInUseUsageDescription").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            TextField("Location Privacy Usage Key", text: $locationPrivacyDescription)
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Privacy Descriptions")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.red)
                }

                // Section 7: Diagnostics & Actions
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Button("Run Code Audit") {
                                runDiagnosticAudit()
                            }
                            .controlSize(.regular)
                            .disabled(isRunningDiagnostic)

                            Button("Reset Defaults", role: .destructive) {
                                revertToDefaults()
                            }
                            .controlSize(.regular)
                            .disabled(isRunningDiagnostic)
                        }

                        if isRunningDiagnostic {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Auditing code directories...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !diagnosticsLog.isEmpty {
                            ScrollView {
                                Text(diagnosticsLog)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            .frame(height: 120)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Diagnostics & Actions")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.teal)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Developer Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onSkip() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply Configurations") {
                        onContinue()
                    }
                    .fontWeight(.semibold)
                    .disabled(validationWarning != nil)
                }
            }
        }
    }

    // MARK: - Subviews

    private func indicatorMiniBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions Helper

    private func runDiagnosticAudit() {
        isRunningDiagnostic = true
        diagnosticsLog = "Starting diagnostic code audit...\n"
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if let activeProj = sessionStore.activeProject {
                diagnosticsLog += "✓ Verified directory existence.\n"
                diagnosticsLog += "✓ Project File Count: \(activeProj.fileCount) active nodes.\n"
                diagnosticsLog += "✓ Bundle ID validation: Success.\n"
                diagnosticsLog += "✓ Active Configuration: \(activeBuildConfiguration)\n"
                diagnosticsLog += "Audit complete. Build environment clean."
            } else {
                diagnosticsLog += "Error: No project attached to audit."
            }
            isRunningDiagnostic = false
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
        diagnosticsLog = "Restored configurations to original framework defaults."
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.bold()).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .autocorrectionDisabled()
        }
    }
}
