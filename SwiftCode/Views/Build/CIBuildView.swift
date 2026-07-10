import SwiftUI

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
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerCard

                        // Adaptive Grid for macOS layouts
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 16) {
                                GroupBox(label: Label("Main Configuration", systemImage: "slider.horizontal.3")) {
                                    configurationCard
                                }
                                .groupBoxStyle(PreferencesGroupBoxStyle())

                                GroupBox(label: Label("Outputs", systemImage: "folder")) {
                                    outputCard
                                }
                                .groupBoxStyle(PreferencesGroupBoxStyle())
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: 16) {
                                GroupBox(label: Label("Build Options", systemImage: "checkmark.square")) {
                                    optionsCard
                                }
                                .groupBoxStyle(PreferencesGroupBoxStyle())

                                actionCard
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("CI Builder")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showYAMLPreview) { yamlPreviewSheet }
            .sheet(isPresented: $showAppDetailsSheet) {
                AppDetailsInfo(
                    appName: $appName,
                    bundleIdentifier: $bundleIdentifier,
                    marketingVersion: $marketingVersion,
                    buildVersion: $buildVersion,
                    supportedDevices: $supportedDevices,
                    onSkip: { showAppDetailsSheet = false; showPrepareCompile = true },
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

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced CI Configuration")
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text("Customize workflow triggers, runner image, artifacts, app metadata, and compile behavior.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
    }

    private var configurationCard: some View {
        VStack(spacing: 12) {
            labeledField("Project Name", text: $projectName)
            labeledField("Scheme", text: $schemeName)
            labeledField("Branch", text: $triggerBranch)

            Picker("Trigger", selection: $triggerMode) {
                ForEach(AssistCIFunctions.BuildYMLConfig.TriggerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }

            Picker("Runner", selection: $runnerImage) {
                ForEach(AssistCIFunctions.BuildYMLConfig.RunnerImage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Timeout: \(Int(timeoutMinutes)) min").font(.caption).foregroundStyle(.secondary)
                Slider(value: $timeoutMinutes, in: 5...180, step: 5)
            }

            Picker("Xcode", selection: $xcodeVersion) {
                Text("16.2").tag("16.2")
                Text("16.1").tag("16.1")
                Text("16.0").tag("16.0")
                Text("15.4").tag("15.4")
            }
            .pickerStyle(.segmented)

            Picker("Build Configuration", selection: $buildConfiguration) {
                ForEach(AssistCIFunctions.BuildYMLConfig.BuildConfiguration.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Target", selection: $destinationType) {
                Text("Device").tag(AssistCIFunctions.BuildYMLConfig.DestinationType.device)
                Text("Simulator").tag(AssistCIFunctions.BuildYMLConfig.DestinationType.simulator)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 8)
    }

    private var outputCard: some View {
        VStack(spacing: 12) {
            labeledField("Output Directory", text: $outputDirectory)
            labeledField("Output Name", text: $outputName)

            Picker("Artifact Export", selection: $exportFormat) {
                ForEach(AssistCIFunctions.BuildYMLConfig.ExportFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 8)
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Run tests", isOn: $includeTests)
            Toggle("Run lint step", isOn: $includeLint)
            Toggle("Clean before archive", isOn: $cleanBuild)
            Toggle("Fail fast (set -e)", isOn: $failFast)
            Toggle("Cache DerivedData", isOn: $includeCaching)
            Toggle("Upload build logs artifact", isOn: $uploadLogsArtifact)
            Toggle("Cancel old runs on same branch", isOn: $includeConcurrencyControl)
        }
        .padding(.vertical, 8)
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button {
                generatedYAMLText = AssistCIFunctions.generateBuildYML(config: buildConfig)
                showYAMLPreview = true
            } label: {
                Label("Preview build.yml", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button { showAppDetailsSheet = true } label: {
                HStack {
                    if isBuilding { ProgressView().scaleEffect(0.8).padding(.trailing, 4) }
                    Text(isBuilding ? "Building..." : "Continue to App Details")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.large)
            .disabled(isBuilding)
        }
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { showYAMLPreview = false } } }
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

                await MainActor.run {
                    sessionStore.updateCIBuildConfiguration(ciConfig, for: project)
                    sessionStore.refreshFileTree(for: project)
                    isSuccess = true
                    statusMessage = "Generated .github/workflows/build.yml in your project."
                    isBuilding = false
                    showStatusAlert = true
                }
            } catch {
                await MainActor.run {
                    isSuccess = false
                    statusMessage = error.localizedDescription
                    isBuilding = false
                    showStatusAlert = true
                }
            }
        }
    }
}
