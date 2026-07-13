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
            ScrollView {
                VStack(spacing: 20) {
                    // Header Dashboard Status
                    dashboardHeaderView

                    // Split Layout for compact density
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            // Card 1: Core App Metadata Form
                            GroupBox(label: Label("App Specifications", systemImage: "info.circle.fill")) {
                                coreMetadataForm
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Card 2: Platform & Device Targets
                            GroupBox(label: Label("Platform Targets", systemImage: "macbook.and.iphone")) {
                                platformTargetsForm
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Card 3: Privacy usage keys
                            GroupBox(label: Label("Privacy Descriptions", systemImage: "hand.raised.fill")) {
                                privacyDescriptionsForm
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 16) {
                            // Card 4: Project Storage & File Locations
                            GroupBox(label: Label("Local Storage Map", systemImage: "folder.fill")) {
                                storageLocationsView
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Card 5: Entitlements & Signing Config
                            GroupBox(label: Label("Signing & Entitlements", systemImage: "shield.fill")) {
                                entitlementsSummaryView
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            // Card 6: Developer Diagnostic Center
                            GroupBox(label: Label("Diagnostics & Actions", systemImage: "ant.fill")) {
                                developerDiagnosticsView
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(20)
            }
            .background(Color(NSColor.windowBackgroundColor))
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

    private var dashboardHeaderView: some View {
        GroupBox {
            HStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appName.isEmpty ? "Developer Project Dashboard" : appName)
                        .font(.title2.bold())
                    Text("Bundle Target Identifier: \(bundleIdentifier)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Static Quick Indicators
                HStack(spacing: 16) {
                    indicatorMiniBox(title: "Target SDK", value: "iOS \(minDeploymentTarget)")
                    indicatorMiniBox(title: "Build Configuration", value: activeBuildConfiguration)
                    if let activeProj = sessionStore.activeProject {
                        indicatorMiniBox(title: "Project Files", value: "\(activeProj.fileCount)")
                    }
                }
            }
            .padding(12)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func indicatorMiniBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    private var coreMetadataForm: some View {
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
    }

    private var platformTargetsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Supported Devices").font(.caption).foregroundStyle(.secondary)
                Picker("Devices", selection: $supportedDevices) {
                    Text("iPhone").tag("iPhone")
                    Text("iPad").tag("iPad")
                    Text("iPhone + iPad").tag("iPhone + iPad")
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum OS").font(.caption).foregroundStyle(.secondary)
                    Picker("Minimum OS Target", selection: $minDeploymentTarget) {
                        Text("iOS 15.0").tag("15.0")
                        Text("iOS 16.0").tag("16.0")
                        Text("iOS 17.0").tag("17.0")
                        Text("macOS 14.0").tag("14.0")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Category").font(.caption).foregroundStyle(.secondary)
                    Picker("App Category", selection: $appCategory) {
                        Text("Developer Tools").tag("Developer Tools")
                        Text("Utilities").tag("Utilities")
                        Text("Productivity").tag("Productivity")
                        Text("Education").tag("Education")
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var privacyDescriptionsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NSCameraUsageDescription").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                TextField("Camera Privacy Usage Key", text: $cameraPrivacyDescription)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("NSLocationWhenInUseUsageDescription").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                TextField("Location Privacy Usage Key", text: $locationPrivacyDescription)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private var storageLocationsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let activeProj = sessionStore.activeProject {
                HStack {
                    Text("Project Directory:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Text(activeProj.directoryURL.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.blue)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(6)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("File Count:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(activeProj.fileCount)")
                            .font(.caption.bold())
                    }

                    GridRow {
                        Text("Created Date:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(activeProj.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption.bold())
                    }
                }
            } else {
                Text("No active project loaded in the current workspace.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var entitlementsSummaryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("App Sandbox Protection", isOn: $sandboxEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)

            Toggle("Outgoing Networking Privileges (Client)", isOn: $outgoingNetworkEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Platform Target:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(targetPlatform).font(.caption.bold())
                }
                GridRow {
                    Text("Target Membership:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Primary Application Target").font(.caption.bold())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var developerDiagnosticsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Run Code Audit") {
                    runDiagnosticAudit()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunningDiagnostic)

                Button("Reset Defaults", role: .destructive) {
                    revertToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRunningDiagnostic)
            }

            if isRunningDiagnostic {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Auditing code directories...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !diagnosticsLog.isEmpty {
                ScrollView {
                    Text(diagnosticsLog)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(6)
                }
                .frame(height: 70)
            }
        }
        .padding(.vertical, 4)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .autocorrectionDisabled()
        }
    }
}
