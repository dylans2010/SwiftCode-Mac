import SwiftUI

public struct BuildingXcodeProject: View {
    @Environment(\.dismiss) private var dismiss

    // Shared API reference
    private var api: XcodeBuildAPI {
        XcodeBuildAPI.shared
    }

    // Configuration Fields (synchronized from defaults or active project)
    @State private var projectName = ""
    @State private var scheme = ""
    @State private var bundleIdentifier = ""
    @State private var organizationIdentifier = "com.example"
    @State private var deploymentTarget = "16.0"
    @State private var targetPlatform = "iOS"

    // Component States
    @State private var isConfiguring = true
    @State private var isPerformingAction = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Xcode Project Generator")
                        .font(.headline)
                    Text("Powered by XcodeGen Integration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 16)

            if isConfiguring {
                // Step 1: Configuration Form
                ScrollView {
                    XcodeProjectDetails(
                        projectName: $projectName,
                        scheme: $scheme,
                        bundleIdentifier: $bundleIdentifier,
                        organizationIdentifier: $organizationIdentifier,
                        deploymentTarget: $deploymentTarget,
                        targetPlatform: $targetPlatform,
                        onGenerate: {
                            isConfiguring = false
                            startVerificationAndGeneration()
                        },
                        onCancel: {
                            api.completeProjectGeneration(success: false)
                            dismiss()
                        }
                    )
                }
            } else {
                // Step 2: Action Status, Logs, and Diagnostics View
                VStack(alignment: .leading, spacing: 16) {
                    // Status summary card
                    VStack(alignment: .leading, spacing: 12) {
                        statusRow(label: "Current Stage:", value: api.currentStage, icon: "hourglass", color: .blue)
                        statusRow(label: "XcodeGen Status:", value: api.xcodegenState.rawValue.capitalized, icon: "cube.fill", color: stateColor(for: api.xcodegenState))

                        if api.xcodegenState == .installing {
                            statusRow(label: "Installation Progress:", value: api.installationStatusString, icon: "arrow.down.circle", color: .purple)
                        }

                        statusRow(label: "Project Validation:", value: api.activeGenerationError == nil ? "Pending Verification" : "Failed", icon: "checkmark.seal", color: api.activeGenerationError == nil ? .green : .red)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    // Diagnostics / Errors display
                    if let error = api.activeGenerationError {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("Failure Stage: \(error.stage)")
                                    .font(.headline)
                                    .foregroundColor(.red)
                            }

                            Text(error.message)
                                .font(.body)
                                .foregroundStyle(.secondary)

                            if let recovery = error.suggestedRecovery {
                                Text("Suggested Recovery: \(recovery)")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            HStack {
                                Button("Retry Action") {
                                    startVerificationAndGeneration()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)

                                Button("Back to Config") {
                                    isConfiguring = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    } else if api.xcodegenState == .missing {
                        // XcodeGen component installation request
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "questionmark.circle.fill")
                                    .foregroundColor(.yellow)
                                Text("XcodeGen Component Missing")
                                    .font(.headline)
                            }
                            Text("SwiftCode requires XcodeGen to automatically generate production-ready Xcode projects from project.yml configurations.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !api.checkHomebrewInstallation() {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Homebrew is missing!")
                                        .font(.caption.bold())
                                        .foregroundColor(.red)
                                    Text("XcodeGen installation requires Homebrew. Please install Homebrew by visiting https://brew.sh, or manually install XcodeGen in your system.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                            }

                            HStack {
                                Button("Install Component") {
                                    Task {
                                        _ = await api.installXcodeGen()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(!api.checkHomebrewInstallation() || api.xcodegenState == .installing)

                                Button("Cancel Build") {
                                    api.completeProjectGeneration(success: false)
                                    dismiss()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.05))
                        .cornerRadius(12)
                    }

                    // Live Log View
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Execution Logs")
                                .font(.headline)
                            Spacer()
                            CopyLogsButton(logs: api.currentLogs.joined(separator: "\n"))
                            Button("Close") {
                                api.completeProjectGeneration(success: false)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(api.currentLogs, id: \.self) { log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(8)
                        .frame(height: 120)
                        .background(Color.black)
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            initializeDefaults()
        }
    }

    private func initializeDefaults() {
        projectName = api.determineProductName()
        scheme = projectName
        bundleIdentifier = api.determineBundleIdentifier()
    }

    private func startVerificationAndGeneration() {
        isPerformingAction = true
        Task {
            // Verify XcodeGen installation
            let state = await api.checkXcodeGenInstallation()
            if state != .installed {
                isPerformingAction = false
                return
            }

            // Run project generation
            let success = await api.generateProjectWithXcodeGen(
                projectName: projectName,
                scheme: scheme,
                bundleIdentifier: bundleIdentifier,
                organizationIdentifier: organizationIdentifier,
                deploymentTarget: deploymentTarget,
                targetPlatform: targetPlatform
            )

            isPerformingAction = false
            if success {
                // Continue directly into existing build pipeline!
                api.completeProjectGeneration(success: true)
                dismiss()
            }
        }
    }

    private func statusRow(label: String, value: String, icon: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .bold()
                .foregroundStyle(color)
        }
        .font(.subheadline)
    }

    private func stateColor(for state: XcodeGenInstallationState) -> Color {
        switch state {
        case .installed: return .green
        case .missing: return .yellow
        case .installing: return .purple
        case .failed: return .red
        }
    }
}

// MARK: - XcodeProjectDetailsSheet

public struct XcodeProjectDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var appName = "My App"
    @State private var bundleIdentifier = "com.example.myapp"
    @State private var minOSVersion = "16.0"
    @State private var targetPlatform = "iOS"
    @State private var appCategory = "Developer Tools"
    @State private var appVersion = "1.0"
    @State private var buildNumber = "1"
    @State private var destinations = ["iphonesimulator", "iphoneos", "macosx"]
    @State private var newDestination = ""
    @State private var isUpdating = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Info
            HStack {
                Label("Xcode Project Details", systemImage: "hammer.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // App Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Name")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("App Name", text: $appName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Bundle ID
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bundle Identifier")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        TextField("Bundle ID", text: $bundleIdentifier)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Version & Build
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Version")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            TextField("1.0", text: $appVersion)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Build Number")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            TextField("1", text: $buildNumber)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Platform & Min OS
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Platform")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Picker("", selection: $targetPlatform) {
                                Text("iOS").tag("iOS")
                                Text("macOS").tag("macOS")
                                Text("tvOS").tag("tvOS")
                                Text("watchOS").tag("watchOS")
                                Text("visionOS").tag("visionOS")
                            }
                            .pickerStyle(.menu)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Minimum OS")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            TextField("16.0", text: $minOSVersion)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Category
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Picker("", selection: $appCategory) {
                            Text("Developer Tools").tag("Developer Tools")
                            Text("Utilities").tag("Utilities")
                            Text("Productivity").tag("Productivity")
                            Text("Education").tag("Education")
                        }
                        .pickerStyle(.menu)
                    }

                    // Destinations List
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Destinations / SDKs")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        ForEach(destinations, id: \.self) { dest in
                            HStack {
                                Image(systemName: "iphone.badge.play")
                                    .foregroundStyle(.blue)
                                Text(dest)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    destinations.removeAll { $0 == dest }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }

                        HStack {
                            TextField("Add Destination/SDK...", text: $newDestination)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                let trimmed = newDestination.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty && !destinations.contains(trimmed) {
                                    destinations.append(trimmed)
                                    newDestination = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Button(action: saveSettings) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Update .xcodeproj")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isUpdating)
                }
                .padding()
            }
        }
        .onAppear {
            loadProjectSettings()
        }
    }

    private func loadProjectSettings() {
        guard let proj = XcodeBuildAPI.shared.determineActiveProject() else { return }
        let fm = FileManager.default
        let contents = try? fm.contentsOfDirectory(at: proj.url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        if let xcodeproj = proj.url.pathExtension == "xcodeproj" ? proj.url : contents?.first(where: { $0.pathExtension == "xcodeproj" }) {
            if let parsed = try? XcodeProjParse.shared.parse(projectURL: xcodeproj) {
                if let config = parsed.buildConfigurations.first(where: { $0.buildSettings["PRODUCT_BUNDLE_IDENTIFIER"] != nil }) {
                    let settings = config.buildSettings
                    if let bid = settings["PRODUCT_BUNDLE_IDENTIFIER"] {
                        bundleIdentifier = bid
                    }
                    if let ver = settings["MARKETING_VERSION"] {
                        appVersion = ver
                    }
                    if let build = settings["CURRENT_PROJECT_VERSION"] {
                        buildNumber = build
                    }
                    if let name = settings["PRODUCT_NAME"] {
                        appName = name
                    }
                    if let target = settings["IPHONEOS_DEPLOYMENT_TARGET"] {
                        minOSVersion = target
                    } else if let target = settings["MACOSX_DEPLOYMENT_TARGET"] {
                        minOSVersion = target
                    }
                }
            }
        }
    }

    private func saveSettings() {
        isUpdating = true
        Task {
            _ = await XcodeBuildAPI.shared.generateProjectWithXcodeGen(
                projectName: appName,
                scheme: appName,
                bundleIdentifier: bundleIdentifier,
                organizationIdentifier: "com.example",
                deploymentTarget: minOSVersion,
                targetPlatform: targetPlatform
            )
            if let activeProj = ProjectSessionStore.shared.activeProject {
                ProjectSessionStore.shared.refreshFileTree(for: activeProj)
            }
            isUpdating = false
        }
    }
}

// MARK: - XcodeProjectDetails View

public struct XcodeProjectDetails: View {
    @Binding var projectName: String
    @Binding var scheme: String
    @Binding var bundleIdentifier: String
    @Binding var organizationIdentifier: String
    @Binding var deploymentTarget: String
    @Binding var targetPlatform: String

    var onGenerate: () -> Void
    var onCancel: () -> Void

    private var isConfigurationValid: Bool {
        let trimmedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedScheme.isEmpty, !trimmedBundle.isEmpty else { return false }
        if trimmedName.contains("/") || trimmedName.contains("\\") { return false }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        if trimmedBundle.rangeOfCharacter(from: allowed.inverted) != nil {
            return false
        }
        return true
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Project Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Project Name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("MyProject", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: projectName) { _, newVal in
                        scheme = newVal
                    }
                if projectName.contains("/") || projectName.contains("\\") {
                    Text("Project name contains invalid characters.")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            // Scheme Name
            VStack(alignment: .leading, spacing: 4) {
                Text("Scheme Name")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("MyProject", text: $scheme)
                    .textFieldStyle(.roundedBorder)
            }

            // Bundle Identifier
            VStack(alignment: .leading, spacing: 4) {
                Text("Bundle Identifier")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("com.example.myproject", text: $bundleIdentifier)
                    .textFieldStyle(.roundedBorder)

                let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
                if bundleIdentifier.rangeOfCharacter(from: allowed.inverted) != nil {
                    Text("Bundle ID contains invalid characters (only alphanumeric, dot, and dash allowed).")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }

            // Organization Identifier
            VStack(alignment: .leading, spacing: 4) {
                Text("Organization Identifier (Optional)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("com.example", text: $organizationIdentifier)
                    .textFieldStyle(.roundedBorder)
            }

            // Deployment Target
            VStack(alignment: .leading, spacing: 4) {
                Text("Deployment Target (Optional)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("16.0", text: $deploymentTarget)
                    .textFieldStyle(.roundedBorder)
            }

            // Target Platform
            VStack(alignment: .leading, spacing: 4) {
                Text("Target Platform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $targetPlatform) {
                    Text("iOS").tag("iOS")
                    Text("macOS").tag("macOS")
                    Text("tvOS").tag("tvOS")
                    Text("watchOS").tag("watchOS")
                    Text("visionOS").tag("visionOS")
                }
                .pickerStyle(.segmented)
            }

            Divider()
                .padding(.vertical, 8)

            // API Auto-resolved Configurations Info
            VStack(alignment: .leading, spacing: 6) {
                Text("Auto-Resolved Configurations")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Group {
                    apiMetadataRow(label: "Project Root", val: XcodeBuildAPI.shared.resolveProjectRoot().lastPathComponent)
                    apiMetadataRow(label: "Sources Dir", val: XcodeBuildAPI.shared.resolveSourceDirectory())
                    apiMetadataRow(label: "Output Dir", val: "build/")
                    apiMetadataRow(label: "DerivedData", val: "build/DerivedData/")
                }
                .font(.system(size: 11))
            }

            Spacer()

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Spacer()

                Button("Generate Project", action: onGenerate)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isConfigurationValid)
            }
            .padding(.top, 12)
        }
    }

    private func apiMetadataRow(label: String, val: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(val)
                .foregroundStyle(.secondary)
        }
    }
}
