import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftCodeDeviceModel

/// The physical-device connect window: discover iOS devices over
/// USB or Wi-Fi (`xcrun xcdevice list`), validate the Xcode
/// environment, build with `xcodebuild`, install and launch with
/// `devicectl`/`simctl`, and watch the deployment pipeline, console,
/// sessions and history.
///
/// This is the port of Legacy's whole DeviceConnectKit UI
/// (`SwiftCode/Views/Build/DeviceConnectKit/DeviceConnectView.swift`
/// + `Views/Console/`, `Deployment/`, `Environment/`, `Inspector/`,
/// `Sessions/`, `Settings/`, `Sheets/`, `Sidebar/`, `Toolbar/`,
/// `Components/`): the same sections and actions, rebuilt in SwiftCode
/// style (default accent, no Legacy orange) on the ported
/// `SwiftCodeDeviceModel` managers. SwiftCode's Device Hub covers simulators
/// and remote sessions; this is the missing physical-device side.
/// Hosting and menu wiring are on the integration list: this view is
/// presented with `NSHostingController`, as `SettingsPanes.swift`
/// already does for `PaywallView`.
@MainActor
struct DeviceConnectView: View {
    @State private var selection = DeviceConnectSection.devices
    @State private var deviceManager = DeviceConnectDeviceManager.shared
    @State private var deploymentManager = DeviceConnectDeploymentManager.shared
    @State private var buildManager = DeviceConnectBuildManager.shared
    @State private var runtimeManager = DeviceConnectRuntimeManager.shared
    @State private var consoleManager = DeviceConnectConsoleManager.shared
    @State private var environmentManager = DeviceConnectEnvironmentManager.shared
    @State private var sessionManager = DeviceConnectSessionManager.shared
    @State private var historyManager = DeviceConnectHistoryManager.shared
    @State private var signingManager = DeviceConnectSigningManager.shared
    @State private var prefs = DeviceConnectPreferencesManager.shared

    @State private var projectPath = ""
    @State private var projectName = ""
    @State private var scheme = ""
    @State private var bundleIdentifier = ""
    @State private var configuration = "Debug"
    @State private var appBundlePath = ""
    @State private var diagnosticsReport = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("DeviceConnect") {
                    ForEach(DeviceConnectSection.allCases) { section in
                        Label(section.title, systemImage: section.symbol)
                            .tag(section)
                    }
                }
                Section("Devices") {
                    if deviceManager.devices.isEmpty {
                        Text(deviceManager.isDiscovering ? "Searching devices…" : "No devices connected")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(deviceManager.devices) { device in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(device.name) (\(device.model))")
                            Text("iOS \(device.osVersion) • \(device.udid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .onTapGesture { deviceManager.selectDevice(device) }
                    }
                }
            }
            .navigationTitle("DeviceConnect")
            .toolbar {
                Button(deviceManager.isDiscovering ? "Stop Scan" : "Scan Devices") {
                    Task {
                        if deviceManager.isDiscovering {
                            await deviceManager.stopDiscovery()
                        } else {
                            await deviceManager.refreshDevices()
                            await deviceManager.startDiscovery()
                        }
                    }
                }
            }
        } detail: {
            switch selection {
            case .devices: devicesSection
            case .deploy: deploySection
            case .console: consoleSection
            case .sessions: sessionsSection
            case .environment: environmentSection
            case .settings: settingsSection
            }
        }
        .task {
            if prefs.autoValidate {
                await environmentManager.validateEnvironment()
            }
            if prefs.autoDiscover {
                await deviceManager.refreshDevices()
            }
        }
    }

    private var devicesSection: some View {
        List {
            Section("Connected devices") {
                if deviceManager.devices.isEmpty {
                    ContentUnavailableView(
                        "No devices connected",
                        systemImage: "iphone",
                        description: Text("Connect an iOS device via USB, or launch an iOS Simulator to build and deploy."))
                }
                ForEach(deviceManager.devices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            Text("\(device.model) • iOS \(device.osVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(device.udid)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if deviceManager.selectedDevice?.udid == device.udid {
                            Label("Selected", systemImage: "checkmark.circle")
                        }
                        Button("Select") { deviceManager.selectDevice(device) }
                    }
                }
            }
            Section("Signing") {
                HStack {
                    Text("Signing status")
                    Spacer()
                    Text(signingManager.signingStatus.description)
                }
                if signingManager.availableIdentities.isEmpty {
                    Text("No signing identities found. Run Verify to check again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(signingManager.availableIdentities, id: \.self) { identity in
                        Text(identity).font(.caption)
                    }
                }
                Button("Verify Signing") {
                    Task { await signingManager.verifySigning() }
                }
            }
        }
        .navigationTitle("Devices")
    }

    private var deploySection: some View {
        Form {
            Section("Target") {
                if let device = deviceManager.selectedDevice {
                    Text("\(device.name) (\(device.model))")
                    Text("iOS \(device.osVersion) • \(device.udid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No target device connected")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Project") {
                HStack {
                    TextField("Project (.xcodeproj)", text: $projectPath)
                    Button("Choose…") { chooseProject() }
                }
                TextField("Project name", text: $projectName)
                TextField("Scheme", text: $scheme)
                Picker("Configuration", selection: $configuration) {
                    Text("Debug").tag("Debug")
                    Text("Release").tag("Release")
                }
                TextField("Bundle identifier", text: $bundleIdentifier)
                TextField("App bundle (.app, optional)", text: $appBundlePath)
                Text("Save the workspace before deploying: the pipeline builds the files on disk as they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Deployment pipeline") {
                HStack {
                    Text(deploymentManager.currentStageDescription)
                    Spacer()
                    if deploymentManager.isDeploying {
                        ProgressView()
                    }
                }
                Button("Deploy") {
                    Task {
                        await deploymentManager.startDeployment(
                            device: deviceManager.selectedDevice ?? ConnectedDevice(
                                name: "Unknown", model: "Unknown", productType: "", platform: "iOS",
                                osVersion: "", buildVersion: "", architecture: "arm64", udid: ""),
                            projectName: projectName.isEmpty ? "App" : projectName,
                            projectPath: projectPath,
                            scheme: scheme,
                            appBundleURL: URL(fileURLWithPath: appBundlePath),
                            bundleIdentifier: bundleIdentifier)
                    }
                }
                .disabled(deviceManager.selectedDevice == nil || projectPath.isEmpty || scheme.isEmpty || bundleIdentifier.isEmpty || deploymentManager.isDeploying)
                HStack {
                    Button("Run App") {
                        Task {
                            guard let device = deviceManager.selectedDevice else { return }
                            let pid = try? await DeviceConnectLaunchService().launch(deviceUDID: device.udid, bundleIdentifier: bundleIdentifier)
                            if let pid {
                                runtimeManager.startMonitoring(deviceUDID: device.udid, bundleID: bundleIdentifier, pid: pid)
                            }
                        }
                    }
                    .disabled(deviceManager.selectedDevice == nil || bundleIdentifier.isEmpty)
                    Button("Stop App") {
                        Task {
                            guard let device = deviceManager.selectedDevice else { return }
                            _ = try? await DeviceConnectRuntimeService().stop(deviceUDID: device.udid, bundleIdentifier: bundleIdentifier)
                            runtimeManager.stopMonitoring(deviceUDID: device.udid)
                        }
                    }
                    .disabled(deviceManager.selectedDevice == nil || bundleIdentifier.isEmpty)
                }
                if !runtimeManager.metrics.isAvailable {
                    Text("Live CPU/memory readings are not available for apps on a tethered device; the monitor reports whether the process is still running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Build") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(buildManager.buildStatus.description)
                }
                if !buildManager.errors.isEmpty {
                    ForEach(Array(buildManager.errors.enumerated()), id: \.offset) { _, issue in
                        Text(issue.message).foregroundStyle(.red)
                    }
                }
                if !buildManager.warnings.isEmpty {
                    ForEach(Array(buildManager.warnings.enumerated()), id: \.offset) { _, issue in
                        Text(issue.message).foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Deploy")
    }

    private var consoleSection: some View {
        VStack(spacing: 0) {
            Picker("Console", selection: $consoleManager.selectedConsoleTab) {
                Text("Build").tag(0)
                Text("Runtime").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(8)
            List(consoleManager.selectedConsoleTab == 0 ? consoleManager.buildLogs : consoleManager.runtimeLogs) { log in
                HStack(alignment: .top, spacing: 6) {
                    Text(log.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("[\(log.severity.rawValue)]")
                        .font(.caption)
                        .foregroundStyle(log.severity == .error ? .red : log.severity == .warning ? .orange : .secondary)
                    Text(log.message)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            HStack {
                Button("Clear") { consoleManager.clearLogs() }
                Spacer()
                Button("Diagnostics Report") {
                    Task {
                        diagnosticsReport = (try? await DiagnosticsCommand().execute()) ?? "Diagnostics failed."
                    }
                }
            }
            .padding(8)
            if !diagnosticsReport.isEmpty {
                ScrollView {
                    Text(diagnosticsReport)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
            }
        }
        .navigationTitle("Console")
    }

    private var sessionsSection: some View {
        List {
            Section("Active session") {
                if let session = sessionManager.activeSession {
                    DeviceConnectSessionRow(session: session)
                    Button("End Session") {
                        sessionManager.endActiveSession(finalStatus: .terminated)
                    }
                } else {
                    Text("No active session").foregroundStyle(.secondary)
                }
            }
            Section("History") {
                if sessionManager.sessionsHistory.isEmpty && historyManager.historyItems.isEmpty {
                    Text("No sessions yet").foregroundStyle(.secondary)
                }
                ForEach(sessionManager.sessionsHistory) { session in
                    DeviceConnectSessionRow(session: session)
                }
                ForEach(historyManager.historyItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.projectName)
                            Text("\(item.deviceName) • \(item.timestamp, style: .date)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.deployResult.description)
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }

    private var environmentSection: some View {
        List {
            Section("Environment") {
                DeviceConnectInspectorRow(label: "Xcode path", value: environmentManager.currentEnvironment.xcodePath ?? "Not found")
                DeviceConnectInspectorRow(label: "Xcode version", value: environmentManager.currentEnvironment.xcodeVersion ?? "Not found")
                DeviceConnectInspectorRow(label: "macOS", value: environmentManager.currentEnvironment.macOSVersion)
                DeviceConnectInspectorRow(label: "Swift", value: environmentManager.currentEnvironment.swiftVersion ?? "Not found")
                DeviceConnectInspectorRow(label: "iOS SDK", value: environmentManager.currentEnvironment.hasiOSSDK ? "Available" : "Missing")
                DeviceConnectInspectorRow(label: "Simulator SDK", value: environmentManager.currentEnvironment.hasSimulatorSDK ? "Available" : "Missing")
                DeviceConnectInspectorRow(label: "Signing", value: environmentManager.currentEnvironment.isSigningSetup ? "Configured" : "Unverified")
                Button(environmentManager.isValidating ? "Validating…" : "Validate Environment") {
                    Task { await environmentManager.validateEnvironment() }
                }
                .disabled(environmentManager.isValidating)
            }
            Section("Diagnostics") {
                if environmentManager.diagnostics.isEmpty {
                    Text("No diagnostics yet. Run Validate Environment.")
                        .foregroundStyle(.secondary)
                }
                ForEach(environmentManager.diagnostics, id: \.self) { diagnostic in
                    Text(diagnostic)
                }
            }
            Section("Derived Data") {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(OutputFormatter.formatBytes(environmentManager.derivedDataSize))
                }
                Button(environmentManager.isDerivedDataClearing ? "Clearing…" : "Clear DerivedData") {
                    Task { await environmentManager.clearDerivedData() }
                }
                .disabled(environmentManager.isDerivedDataClearing)
            }
        }
        .navigationTitle("Environment")
    }

    private var settingsSection: some View {
        Form {
            Toggle("Discover devices automatically", isOn: $prefs.autoDiscover)
            Toggle("Validate environment on open", isOn: $prefs.autoValidate)
            Toggle("Save before deploy", isOn: $prefs.autoSaveBeforeDeploy)
            Toggle("Launch after install", isOn: $prefs.autoLaunch)
            Toggle("Stream logs automatically", isOn: $prefs.autoStreamLogs)
            Toggle("Show notifications", isOn: $prefs.showNotifications)
            Toggle("Keep history", isOn: $prefs.keepHistory)
            Stepper("Keep at most \(prefs.maxSessionCount) sessions", value: $prefs.maxSessionCount, in: 1...500)
        }
        .navigationTitle("Settings")
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "xcodeproj")].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            if projectName.isEmpty {
                projectName = url.deletingPathExtension().lastPathComponent
            }
        }
    }
}

enum DeviceConnectSection: String, CaseIterable, Identifiable {
    case devices, deploy, console, sessions, environment, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return "Devices"
        case .deploy: return "Deploy"
        case .console: return "Console"
        case .sessions: return "Sessions"
        case .environment: return "Environment"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .devices: return "iphone"
        case .deploy: return "arrow.triangle.2.circlepath"
        case .console: return "terminal"
        case .sessions: return "clock"
        case .environment: return "checkmark.shield"
        case .settings: return "gear"
        }
    }
}

private struct DeviceConnectSessionRow: View {
    var session: DeviceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(session.projectName) on \(session.deviceName)")
            HStack {
                Text(session.configuration)
                Text(session.deploymentStatus.description)
                Text(session.runtimeStatus.description)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct DeviceConnectInspectorRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
