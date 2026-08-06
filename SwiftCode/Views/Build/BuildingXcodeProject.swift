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
    @State private var selectedSDKToAdd = ""
    @State private var isUpdating = false

    private var availableSDKsForSelection: [DetectedSDK] {
        if XcodeBuildManager.shared.detectedSDKs.isEmpty {
            return [
                DetectedSDK(identifier: "macosx", platform: "macOS", displayName: "macOS", version: ""),
                DetectedSDK(identifier: "iphoneos", platform: "iOS", displayName: "iOS", version: ""),
                DetectedSDK(identifier: "iphonesimulator", platform: "iOS Simulator", displayName: "iOS Simulator", version: ""),
                DetectedSDK(identifier: "watchos", platform: "watchOS", displayName: "watchOS", version: ""),
                DetectedSDK(identifier: "watchsimulator", platform: "watchOS Simulator", displayName: "watchOS Simulator", version: ""),
                DetectedSDK(identifier: "appletvos", platform: "tvOS", displayName: "tvOS", version: ""),
                DetectedSDK(identifier: "appletvsimulator", platform: "tvOS Simulator", displayName: "tvOS Simulator", version: "")
            ]
        }
        return XcodeBuildManager.shared.detectedSDKs
    }

    // Advanced Metrics & Diagnostics
    @State private var numberOfTargets = 0
    @State private var numberOfFiles = 0
    @State private var numberOfSwiftFiles = 0
    @State private var activeGitBranch = "Checking..."
    @State private var buildConfigurationsList: [String] = ["Debug", "Release"]
    @State private var sourceDirectoryName = ""
    @State private var xcodegenVersion = "Checking..."
    @State private var showingDiagnosticsPopover = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Elegant Visual Header
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.12))
                        .frame(width: 46, height: 48)
                    Image(systemName: "hammer.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Project Inspector")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Real-Time Project Configuration & Metrics")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button {
                            showingDiagnosticsPopover = true
                        } label: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingDiagnosticsPopover) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("IDE Diagnostics")
                                    .font(.headline)
                                Divider()
                                LabeledContent("XcodeGen Version", value: xcodegenVersion)
                                LabeledContent("Swift Compiler Target", value: "Apple Swift 6.0")
                                LabeledContent("Active SDK Platforms", value: "macOS, iOS, simulator")
                            }
                            .padding()
                            .frame(width: 250)
                        }
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Panel")
                }
            }
            .padding()
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Modern High-Fidelity Stats Dashboard
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WORKSPACE METRICS")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            MetricCard(title: "Targets Count", value: "\(numberOfTargets)", icon: "target")
                            MetricCard(title: "Total Source Files", value: "\(numberOfFiles) items", icon: "doc.text")
                            MetricCard(title: "Swift Files", value: "\(numberOfSwiftFiles)", icon: "swift")
                            MetricCard(title: "Git Branch", value: activeGitBranch, icon: "arrow.triangle.branch")
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Active Directory:")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(sourceDirectoryName.isEmpty ? "default" : sourceDirectoryName)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                            }
                            HStack {
                                Text("Configurations:")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(buildConfigurationsList.joined(separator: ", "))
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.12), lineWidth: 1))

                    // App Name & Bundle ID configuration
                    GroupBox(label: Label("APP IDENTITY", systemImage: "person.crop.square")) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("App Name")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("App Name", text: $appName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bundle Identifier")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                TextField("Bundle ID", text: $bundleIdentifier)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Version & Build Number Config
                    GroupBox(label: Label("VERSIONING", systemImage: "tag.fill")) {
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
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Target deployment Platform & Minimum OS
                    GroupBox(label: Label("DEPLOYMENT TARGET", systemImage: "play.circle")) {
                        VStack(spacing: 12) {
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
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Destinations & SDKs Manager list
                    GroupBox(label: Label("DESTINATIONS / SDKS", systemImage: "iphone.badge.play")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(destinations, id: \.self) { dest in
                                HStack {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
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
                                Picker("Select SDK", selection: $selectedSDKToAdd) {
                                    Text("Select SDK...").tag("")
                                    ForEach(availableSDKsForSelection) { sdk in
                                        Text("\(sdk.displayName) (\(sdk.identifier))").tag(sdk.identifier)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)

                                Button {
                                    if !selectedSDKToAdd.isEmpty && !destinations.contains(selectedSDKToAdd) {
                                        destinations.append(selectedSDKToAdd)
                                        selectedSDKToAdd = ""
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(selectedSDKToAdd.isEmpty ? .secondary : .green)
                                }
                                .buttonStyle(.plain)
                                .disabled(selectedSDKToAdd.isEmpty)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    Button(action: saveSettings) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Save & Re-generate XcodeProj")
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
        .frame(minWidth: 420, minHeight: 550)
        .onAppear {
            loadProjectSettings()
            checkXcodeGen()
            loadAdvancedMetrics()
            Task {
                await XcodeBuildManager.shared.detectAvailableSDKs()
            }
        }
    }

    private func checkXcodeGen() {
        Task {
            let pathStr = "/usr/local/bin/xcodegen"
            if FileManager.default.fileExists(atPath: pathStr) {
                xcodegenVersion = "Installed (1.0+)"
            } else {
                xcodegenVersion = "Not found (using system binary)"
            }
        }
    }

    private func loadAdvancedMetrics() {
        guard let proj = XcodeBuildAPI.shared.determineActiveProject() else { return }
        sourceDirectoryName = proj.url.path

        // Asynchronously scan files and git branch
        Task.detached { [proj] in
            let fm = FileManager.default
            var fileCount = 0
            var swiftCount = 0

            if let enumerator = fm.enumerator(
                at: proj.url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) {
                // Iterate using nextObject() to avoid makeIterator() in async contexts
                while let obj = enumerator.nextObject() {
                    guard let fileURL = obj as? URL else { continue }
                    let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                    if isFile {
                        fileCount += 1
                        if fileURL.pathExtension.lowercased() == "swift" {
                            swiftCount += 1
                        }
                    }
                }
            }

            // Fetch active git branch synchronously in this background task
            var resolvedBranch = "main"
            do {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                task.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
                task.currentDirectoryURL = proj.url

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()

                try task.run()
                task.waitUntilExit()

                if task.terminationStatus == 0,
                   let data = try? pipe.fileHandleForReading.readToEnd(),
                   let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !branch.isEmpty {
                    resolvedBranch = branch
                } else {
                    resolvedBranch = "main (default)"
                }
            } catch {
                resolvedBranch = "main"
            }

            // Publish results back to the main actor
            await MainActor.run {
                self.numberOfFiles = fileCount
                self.numberOfSwiftFiles = swiftCount
                self.activeGitBranch = resolvedBranch
            }
        }
    }

    private func loadProjectSettings() {
        guard let proj = XcodeBuildAPI.shared.determineActiveProject() else { return }
        if let savedDests = ProjectSessionStore.shared.activeProject?.destinations {
            self.destinations = savedDests
        } else {
            self.destinations = ["iphonesimulator", "iphoneos", "macosx"]
        }
        let fm = FileManager.default
        let contents = try? fm.contentsOfDirectory(at: proj.url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        if let xcodeproj = proj.url.pathExtension == "xcodeproj" ? proj.url : contents?.first(where: { $0.pathExtension == "xcodeproj" }) {
            if let parsed = try? XcodeProjParse.shared.parse(projectURL: xcodeproj) {
                numberOfTargets = parsed.targets.count
                buildConfigurationsList = parsed.buildConfigurations.map { $0.name }

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
            if let activeProj = ProjectSessionStore.shared.activeProject {
                ProjectSessionStore.shared.updateProjectDestinations(destinations, for: activeProj)
            }
            _ = await XcodeBuildAPI.shared.generateProjectWithXcodeGen(
                projectName: appName,
                scheme: appName,
                bundleIdentifier: bundleIdentifier,
                organizationIdentifier: "com.example",
                deploymentTarget: minOSVersion,
                targetPlatform: targetPlatform,
                destinations: destinations
            )
            if let activeProj = ProjectSessionStore.shared.activeProject {
                ProjectSessionStore.shared.refreshFileTree(for: activeProj)
            }
            isUpdating = false
        }
    }
}

// MARK: - MetricCard Helper View

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
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

