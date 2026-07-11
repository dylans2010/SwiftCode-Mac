import SwiftUI

@MainActor
struct CIBuildView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore

    @State private var projectName: String = ""
    @State private var schemeName: String = ""
    @State private var xcodeVersion: String = "16.2"
    @State private var buildConfiguration: AssistCIFunctions.BuildYMLConfig.BuildConfiguration = .release
    @State private var destinationType: AssistCIFunctions.BuildYMLConfig.DestinationType = .device
    @State private var outputDirectory: String = "upload"
    @State private var outputName: String = "AppBuild"
    @State private var triggerBranch: String = "main"
    @State private var triggerMode: AssistCIFunctions.BuildYMLConfig.TriggerMode = .pushAndManual
    @State private var exportFormat: AssistCIFunctions.BuildYMLConfig.ExportFormat = .ipa
    @State private var runnerImage: AssistCIFunctions.BuildYMLConfig.RunnerImage = .macOS14
    @State private var timeoutMinutes: Double = 30
    @State private var includeConcurrencyControl = true

    @State private var includeTests = false
    @State private var includeLint = false
    @State private var cleanBuild = true
    @State private var failFast = true
    @State private var includeCaching = true
    @State private var uploadLogsArtifact = true

    @State private var appName: String = ""
    @State private var bundleIdentifier: String = "com.example.app"
    @State private var marketingVersion: String = "1.0"
    @State private var buildVersion: String = "1"
    @State private var supportedDevices: String = "iPhone + iPad"

    @State private var generatedYAMLText: String = ""
    @State private var showYAMLPreview = false
    @State private var showStatusAlert = false
    @State private var statusMessage = ""
    @State private var isSuccess = false
    @State private var showAppDetailsSheet = false
    @State private var showPrepareCompile = false

    @State private var isBuilding = false
    @State private var lastBuildTriggerAt: Date?
    private let deduplicationWindow: TimeInterval = 8

    private var buildConfig: AssistCIFunctions.BuildYMLConfig {
        AssistCIFunctions.BuildYMLConfig(
            projectName: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
            scheme: schemeName.trimmingCharacters(in: .whitespacesAndNewlines),
            xcodeVersion: xcodeVersion,
            buildConfiguration: buildConfiguration,
            destinationType: destinationType,
            outputDirectory: outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines),
            outputName: outputName.trimmingCharacters(in: .whitespacesAndNewlines),
            triggerBranch: triggerBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            triggerMode: triggerMode,
            includeTests: includeTests,
            includeLint: includeLint,
            cleanBuild: cleanBuild,
            failFast: failFast,
            includeCaching: includeCaching,
            uploadLogsArtifact: uploadLogsArtifact,
            exportFormat: exportFormat,
            runnerImage: runnerImage,
            timeoutMinutes: Int(timeoutMinutes),
            includeConcurrencyControl: includeConcurrencyControl,
            appName: appName.trimmingCharacters(in: .whitespacesAndNewlines),
            bundleIdentifier: bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
            marketingVersion: marketingVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            buildVersion: buildVersion.trimmingCharacters(in: .whitespacesAndNewlines),
            supportedDevices: supportedDevices
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Advanced CI Configuration")
                            .font(.headline)
                        Text("Customize triggers, runner image, artifacts, metadata, and compile behavior.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Project Identification") {
                    TextField("Project Name", text: $projectName)
                    TextField("Scheme", text: $schemeName)
                    TextField("Trigger Branch", text: $triggerBranch)
                }

                Section("Trigger & Environment") {
                    Picker("Trigger Mode", selection: $triggerMode) {
                        ForEach(AssistCIFunctions.BuildYMLConfig.TriggerMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }

                    Picker("macOS Runner", selection: $runnerImage) {
                        ForEach(AssistCIFunctions.BuildYMLConfig.RunnerImage.allCases, id: \.self) { image in
                            Text(image.rawValue).tag(image)
                        }
                    }

                    Picker("Xcode Version", selection: $xcodeVersion) {
                        Text("16.2").tag("16.2")
                        Text("16.1").tag("16.1")
                        Text("16.0").tag("16.0")
                        Text("15.4").tag("15.4")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Timeout Limit: \(Int(timeoutMinutes)) min")
                        Slider(value: $timeoutMinutes, in: 5...180, step: 5)
                    }
                }

                Section("Compilation Settings") {
                    Picker("Build Configuration", selection: $buildConfiguration) {
                        ForEach(AssistCIFunctions.BuildYMLConfig.BuildConfiguration.allCases, id: \.self) { config in
                            Text(config.rawValue).tag(config)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Destination Target", selection: $destinationType) {
                        Text("Device").tag(AssistCIFunctions.BuildYMLConfig.DestinationType.device)
                        Text("Simulator").tag(AssistCIFunctions.BuildYMLConfig.DestinationType.simulator)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Outputs & Artifacts") {
                    TextField("Output Directory", text: $outputDirectory)
                    TextField("Output Name", text: $outputName)

                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(AssistCIFunctions.BuildYMLConfig.ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("CI Options") {
                    Toggle("Run Unit Tests", isOn: $includeTests)
                    Toggle("Run Linter Step", isOn: $includeLint)
                    Toggle("Clean Before Archive", isOn: $cleanBuild)
                    Toggle("Fail Fast (set -e)", isOn: $failFast)
                    Toggle("Enable DerivedData Caching", isOn: $includeCaching)
                    Toggle("Upload Build Logs Artifact", isOn: $uploadLogsArtifact)
                    Toggle("Concurrency Control (Cancel Old Runs)", isOn: $includeConcurrencyControl)
                }

                Section("Actions") {
                    Button {
                        generatedYAMLText = AssistCIFunctions.generateBuildYML(config: buildConfig)
                        showYAMLPreview = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Preview build.yml", systemImage: "doc.text.magnifyingglass")
                            Spacer()
                        }
                    }

                    Button {
                        showAppDetailsSheet = true
                    } label: {
                        HStack {
                            Spacer()
                            if isBuilding {
                                ProgressView().scaleEffect(0.8).padding(.trailing, 4)
                            }
                            Text(isBuilding ? "Building..." : "Continue to App Details")
                                .bold()
                            Spacer()
                        }
                    }
                    .tint(.purple)
                    .disabled(isBuilding)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("CI Builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showYAMLPreview) { yamlPreviewSheet }
            .sheet(isPresented: $showAppDetailsSheet) {
                AppDetailsInfo(
                    appName: $appName,
                    bundleIdentifier: $bundleIdentifier,
                    marketingVersion: $marketingVersion,
                    buildVersion: $buildVersion,
                    supportedDevices: $supportedDevices,
                    onSkip: {
                        showAppDetailsSheet = false
                        showPrepareCompile = true
                    },
                    onContinue: {
                        showAppDetailsSheet = false
                        startBuild()
                    }
                )
                .frame(width: 500, height: 400)
            }
            .sheet(isPresented: $showPrepareCompile) {
                PrepareCompileWaitingView(project: project)
                    .frame(width: 500, height: 400)
            }
            .alert(isSuccess ? "Success" : "Error", isPresented: $showStatusAlert) {
                Button("OK") {
                    if isSuccess {
                        showPrepareCompile = true
                    }
                }
            } message: {
                Text(statusMessage)
            }
            .onAppear {
                projectName = project.name
                let ciConfig = project.ciBuildConfiguration
                schemeName = ciConfig?.schemeName.isEmpty == false ? ciConfig?.schemeName ?? project.name : project.name
                outputName = project.name
                appName = project.name
                bundleIdentifier = ciConfig?.bundleIdentifier ?? "com.example.\(project.name.lowercased())"
            }
        }
    }

    private var yamlPreviewSheet: some View {
        NavigationStack {
            ScrollView {
                Text(generatedYAMLText)
                    .font(.system(size: 11, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .navigationTitle("build.yml")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { showYAMLPreview = false }
                }
            }
        }
        .frame(width: 600, height: 500)
    }

    private func startBuild() {
        guard !isBuilding else { return }
        if let lastBuildTriggerAt, Date().timeIntervalSince(lastBuildTriggerAt) < deduplicationWindow {
            isSuccess = false
            statusMessage = "Build ignored to prevent duplicate triggers. Please wait a few seconds."
            showStatusAlert = true
            return
        }

        guard !buildConfig.projectName.isEmpty, !buildConfig.scheme.isEmpty, !buildConfig.bundleIdentifier.isEmpty else {
            isSuccess = false
            statusMessage = "Project name, scheme, and bundle identifier are required."
            showStatusAlert = true
            return
        }

        isBuilding = true
        lastBuildTriggerAt = Date()

        Task {
            do {
                let workflowDir = project.directoryURL.appendingPathComponent(".github/workflows", isDirectory: true)
                try FileManager.default.createDirectory(at: workflowDir, withIntermediateDirectories: true)

                let yamlText = AssistCIFunctions.generateBuildYML(config: buildConfig)
                try yamlText.write(to: workflowDir.appendingPathComponent("build.yml"), atomically: true, encoding: .utf8)

                let ciConfig = CIBuildConfiguration(
                    platform: .iOSAndIPadOS,
                    deploymentTarget: "16.0",
                    targetDeviceFamily: supportedDevices == "iPhone" ? .iPhone : (supportedDevices == "iPad" ? .iPad : .iPhoneAndIPad),
                    schemeName: buildConfig.scheme,
                    bundleIdentifier: buildConfig.bundleIdentifier
                )

                sessionStore.updateCIBuildConfiguration(ciConfig, for: project)
                sessionStore.refreshFileTree(for: project)
                isSuccess = true
                statusMessage = "Generated .github/workflows/build.yml in your project."
                isBuilding = false
                showStatusAlert = true
            } catch {
                isSuccess = false
                statusMessage = error.localizedDescription
                isBuilding = false
                showStatusAlert = true
            }
        }
    }
}
