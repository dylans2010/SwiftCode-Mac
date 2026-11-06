import SwiftUI

struct WorkflowsCreateView: View {
    let project: Project?
    @Environment(\.dismiss) private var dismiss

    // Trigger specifications
    @State private var triggerPush = true
    @State private var triggerPR = false
    @State private var triggerSchedule = false
    @State private var triggerManual = true
    @State private var cronExpression = "0 0 * * *"
    @State private var branchFilters = "main, develop"
    @State private var tagFilters = "v*"

    // Job specs
    @State private var selectedOS = "macos-latest"
    @State private var matrixBuilds = false
    @State private var matrixOSList = "macos-latest, ubuntu-latest"
    @State private var jobConditions = ""
    @State private var permissionsRead = true
    @State private var permissionsWrite = false

    // Steps configuration
    @State private var checkoutStep = true
    @State private var setupXcode = true
    @State private var setupNode = false
    @State private var cacheDependencies = true
    @State private var runCommand = "swift build"
    @State private var uploadArtifacts = true
    @State private var artifactName = "build-output"
    @State private var artifactPath = ".build/"

    // Advanced Specs
    @State private var customContainers = ""
    @State private var customServices = ""
    @State private var envVariables = "DEVELOPER_DIR=/Applications/Xcode.app"
    @State private var secretNames = "GH_TOKEN, COCOAPODS_KEY"

    // YAML state
    @State private var validationErrors: String? = nil
    @State private var showSuccessAlert = false
    @State private var successMsg = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Panel
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Visual GitHub Actions Workflow Creator", systemImage: "play.circle.fill")
                                .font(.headline)
                                .foregroundColor(.indigo)
                            Text("Visually build triggers, matrix targets, secure environments, and job steps to generate standard GitHub Actions workflow containers.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 1: Workflow Triggers
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Triggers & Event Filters", systemImage: "bolt.fill")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Divider()

                        Toggle("Push Events", isOn: $triggerPush)
                        Toggle("Pull Request Events", isOn: $triggerPR)
                        Toggle("Manual Dispatch (workflow_dispatch)", isOn: $triggerManual)

                        Toggle("Scheduled Run (Cron)", isOn: $triggerSchedule)
                        if triggerSchedule {
                            TextField("Cron expression (e.g. 0 0 * * *)", text: $cronExpression)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Branch Filters (comma separated)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("e.g. main, develop", text: $branchFilters)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tag Filters (comma separated)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("e.g. v*", text: $tagFilters)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 2: Job environment and Matrix targets
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Job Runner & Concurrency Matrix", systemImage: "cpu")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Divider()

                        Picker("Runner OS Target", selection: $selectedOS) {
                            Text("macos-latest").tag("macos-latest")
                            Text("ubuntu-latest").tag("ubuntu-latest")
                            Text("windows-latest").tag("windows-latest")
                        }
                        .pickerStyle(.segmented)

                        Toggle("Matrix Builds (Multi-OS)", isOn: $matrixBuilds)
                        if matrixBuilds {
                            TextField("Matrix OS platforms (comma separated)", text: $matrixOSList)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Job Run Conditions (if)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("e.g. github.ref == 'refs/heads/main'", text: $jobConditions)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 16) {
                            Toggle("Repository Contents: READ", isOn: $permissionsRead)
                            Toggle("Repository Contents: WRITE", isOn: $permissionsWrite)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 3: Job steps hierarchy
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Job Steps Hierarchy", systemImage: "list.number")
                            .font(.headline)
                            .foregroundColor(.green)

                        Divider()

                        Toggle("Checkout repository code (actions/checkout)", isOn: $checkoutStep)
                        Toggle("Configure Xcode Development environment", isOn: $setupXcode)
                        Toggle("Configure Node.js dependency manager", isOn: $setupNode)
                        Toggle("Cache dependencies packages", isOn: $cacheDependencies)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Run execution terminal command")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("Build command...", text: $runCommand)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle("Upload build products (actions/upload-artifact)", isOn: $uploadArtifacts)
                        if uploadArtifacts {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Artifact name...", text: $artifactName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Artifact source directory path...", text: $artifactPath)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 4: Secure environment variables and Secrets
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Secure Environments & Secrets", systemImage: "lock.fill")
                            .font(.headline)
                            .foregroundColor(.purple)

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Global Environment Variables (Key=Value, comma separated)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("e.g. KEY=VALUE, OUT=build/", text: $envVariables)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Required Action Secrets (comma separated keys)")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            TextField("e.g. GH_TOKEN, COCOAPODS_KEY", text: $secretNames)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Section 5: YAML Live editor preview
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Generated workflow.yml Live Preview", systemImage: "doc.text.fill")
                            .font(.headline)
                            .foregroundColor(.gray)

                        Divider()

                        Text(generateYAMLString())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                if let validationErrors = validationErrors {
                    GroupBox {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(validationErrors)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Action buttons
                HStack(spacing: 16) {
                    Button("Save Workflow to .github/workflows/") {
                        saveWorkflowFile()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.bottom, 24)
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Workflow Creator Console")
        .alert("Success", isPresented: $showSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text(successMsg)
        }
        .onAppear {
            loadExistingWorkflow()
        }
    }

    // MARK: - YAML Generator Logic

    private func generateYAMLString() -> String {
        var yaml = ""
        yaml += "name: Visual Created CI\n\n"

        // 1. Triggers
        yaml += "on:\n"
        if triggerPush {
            yaml += "  push:\n"
            let branches = branchFilters.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !branches.isEmpty {
                yaml += "    branches: [ \(branches.map { "\"\($0)\"" }.joined(separator: ", ")) ]\n"
            }
            let tags = tagFilters.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !tags.isEmpty {
                yaml += "    tags: [ \(tags.map { "\"\($0)\"" }.joined(separator: ", ")) ]\n"
            }
        }
        if triggerPR {
            yaml += "  pull_request:\n"
            let branches = branchFilters.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !branches.isEmpty {
                yaml += "    branches: [ \(branches.map { "\"\($0)\"" }.joined(separator: ", ")) ]\n"
            }
        }
        if triggerManual {
            yaml += "  workflow_dispatch:\n"
        }
        if triggerSchedule {
            yaml += "  schedule:\n"
            yaml += "    - cron: \"\(cronExpression)\"\n"
        }
        yaml += "\n"

        // 2. Global Environment variables
        let envs = envVariables.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !envs.isEmpty {
            yaml += "env:\n"
            for env in envs {
                let parts = env.split(separator: "=")
                if parts.count == 2 {
                    yaml += "  \(parts[0]): \"\(parts[1])\"\n"
                }
            }
            yaml += "\n"
        }

        // 3. Permissions
        yaml += "permissions:\n"
        yaml += "  contents: \(permissionsWrite ? "write" : "read")\n\n"

        // 4. Jobs block
        yaml += "jobs:\n"
        yaml += "  build-and-test:\n"
        yaml += "    runs-on: \(selectedOS)\n"

        if matrixBuilds {
            let platforms = matrixOSList.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            yaml += "    strategy:\n"
            yaml += "      matrix:\n"
            yaml += "        os: [ \(platforms.map { "\"\($0)\"" }.joined(separator: ", ")) ]\n"
            yaml += "    runs-on: ${{ matrix.os }}\n"
        }

        if !jobConditions.isEmpty {
            yaml += "    if: \(jobConditions)\n"
        }

        yaml += "    steps:\n"

        if checkoutStep {
            yaml += "      - name: Checkout Repository\n"
            yaml += "        uses: actions/checkout@v4\n"
        }

        if setupXcode {
            yaml += "      - name: Configure Xcode Version\n"
            yaml += "        run: sudo xcode-select -s /Applications/Xcode.app\n"
        }

        if setupNode {
            yaml += "      - name: Configure Node.js environment\n"
            yaml += "        uses: actions/setup-node@v4\n"
            yaml += "        with:\n"
            yaml += "          node-version: \"20\"\n"
        }

        if cacheDependencies {
            yaml += "      - name: Cache dependencies packages\n"
            yaml += "        uses: actions/cache@v4\n"
            yaml += "        with:\n"
            yaml += "          path: .build/\n"
            yaml += "          key: ${{ runner.os }}-xcode-${{ hashFiles('**/Package.swift') }}\n"
        }

        if !runCommand.isEmpty {
            yaml += "      - name: Run Build commands\n"
            yaml += "        run: \(runCommand)\n"
        }

        if uploadArtifacts {
            yaml += "      - name: Upload Build Artifact products\n"
            yaml += "        uses: actions/upload-artifact@v4\n"
            yaml += "        with:\n"
            yaml += "          name: \(artifactName)\n"
            yaml += "          path: \(artifactPath)\n"
        }

        return yaml
    }

    // MARK: - Save Workflow File

    private func saveWorkflowFile() {
        guard let proj = project else {
            self.validationErrors = "Validation Error: No project associated with the session."
            return
        }

        // Validate YAML basic syntax (must have name, jobs, and steps)
        let yamlContent = generateYAMLString()
        if !yamlContent.contains("name:") || !yamlContent.contains("jobs:") || !yamlContent.contains("steps:") {
            self.validationErrors = "Validation Error: The generated YAML fails to conform to GitHub Actions structural configurations."
            return
        }

        // Check if there are unclosed curly braces
        if yamlContent.components(separatedBy: "${{").count != yamlContent.components(separatedBy: "}}").count {
            self.validationErrors = "Validation Error: Mismatched expression syntax '${{' or '}}' detected."
            return
        }

        self.validationErrors = nil

        let workflowsDir = proj.directoryURL.appendingPathComponent(".github/workflows")
        let fileURL = workflowsDir.appendingPathComponent("workflow.yml")

        do {
            try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
            try yamlContent.write(to: fileURL, atomically: true, encoding: .utf8)
            ProjectSessionStore.shared.refreshFileTree(for: proj)

            self.successMsg = "Successfully generated and validated workflow.yml inside .github/workflows/"
            self.showSuccessAlert = true
        } catch {
            self.validationErrors = "System Error: Failed to write workflow.yml file: \(error.localizedDescription)"
        }
    }

    // MARK: - Reopen Existing Workflow

    private func loadExistingWorkflow() {
        guard let proj = project else { return }
        let fileURL = proj.directoryURL.appendingPathComponent(".github/workflows/workflow.yml")

        if FileManager.default.fileExists(atPath: fileURL.path),
           let content = try? String(contentsOf: fileURL, encoding: .utf8) {

            // Reopen values based on existing tags
            if content.contains("push:") { self.triggerPush = true }
            if content.contains("pull_request:") { self.triggerPR = true }
            if content.contains("workflow_dispatch:") { self.triggerManual = true }
            if content.contains("schedule:") { self.triggerSchedule = true }
            if content.contains("strategy:") { self.matrixBuilds = true }
            if content.contains("actions/setup-node") { self.setupNode = true }
            if content.contains("actions/upload-artifact") { self.uploadArtifacts = true }
        }
    }
}
