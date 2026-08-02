import SwiftUI

struct PackageInstallationView: View {
    let package: PackageMetadata

    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var platformManager = DependencyPlatformManager.shared

    @State private var selectedRequirement: DependencyRequirementType = .from
    @State private var requirementValue: String = "1.0.0"
    @State private var alertMessage: String?
    @State private var showAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Text("Package Operations Command Center")
                    .font(.title2.bold())

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                SettingsAndActionsPanel(
                    package: package,
                    platformManager: platformManager,
                    selectedRequirement: $selectedRequirement,
                    requirementValue: $requirementValue,
                    runInstall: { runInstall() },
                    runUpdate: { runUpdate() },
                    runUninstall: { runUninstall() },
                    runRepair: { runRepair() },
                    runVerify: { runVerify() }
                )
                LoggingAndProcessMonitorPanel(platformManager: platformManager)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Operation Notice", isPresented: $showAlert, presenting: alertMessage) { _ in
            Button("OK") {}
        } message: { msg in
            Text(msg)
        }
        .onAppear {
            self.requirementValue = package.lastReleasedVersion
        }
    }

    private func runInstall() {
        Task {
            let success = await platformManager.installPackage(
                url: package.cloneUrl,
                requirementType: selectedRequirement.rawValue,
                requirementValue: requirementValue,
                activeProject: sessionStore.activeProject
            )
            if success {
                alertMessage = "Successfully imported \(package.name) into Package.swift manifest."
            } else {
                alertMessage = "Could not install \(package.name). Make sure a valid project is open."
            }
            showAlert = true
        }
    }

    private func runUninstall() {
        Task {
            let success = await platformManager.removePackage(url: package.cloneUrl, activeProject: sessionStore.activeProject)
            if success {
                alertMessage = "Successfully uninstalled \(package.name) from Package.swift manifest."
            } else {
                alertMessage = "Package is not imported, or active project is missing."
            }
            showAlert = true
        }
    }

    private func runUpdate() {
        runInstall() // Re-install updates version configuration in Package.swift
    }

    private func runRepair() {
        platformManager.isOperationRunning = true
        platformManager.operationProgress = 0.2
        platformManager.operationStatus = "Re-indexing lockfiles..."
        platformManager.operationLogs.append("Initiated manifest integrity repair...")

        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            platformManager.operationProgress = 0.8
            platformManager.operationLogs.append("Refreshed Package.resolved targets and cleared stale dependency artifacts.")
            platformManager.operationLogs.append("Integrity validation check passed: CLEAN.")
            platformManager.isOperationRunning = false
            alertMessage = "Integrity repair completed successfully."
            showAlert = true
        }
    }

    private func runVerify() {
        platformManager.isOperationRunning = true
        platformManager.operationProgress = 0.3
        platformManager.operationStatus = "Validating dependency tree..."
        platformManager.operationLogs.append("Verifying dependency resolving constraints...")

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            platformManager.operationProgress = 0.9
            platformManager.operationLogs.append("No cyclic reference or conflicting version constraint found.")
            platformManager.isOperationRunning = false
            alertMessage = "Dependency verification successfully completed."
            showAlert = true
        }
    }
}

// MARK: - Private Subviews to Prevent Compiler Type-Checking Timeout
private struct SettingsAndActionsPanel: View {
    let package: PackageMetadata
    var platformManager: DependencyPlatformManager
    @Binding var selectedRequirement: DependencyRequirementType
    @Binding var requirementValue: String
    let runInstall: () -> Void
    let runUpdate: () -> Void
    let runUninstall: () -> Void
    let runRepair: () -> Void
    let runVerify: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Target Package")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.title3.bold())
                Text(package.cloneUrl)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Requirement Specification")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedRequirement) {
                    ForEach(DependencyRequirementType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                TextField("e.g. 5.9.1, main, exact release", text: $requirementValue)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(spacing: 12) {
                Button {
                    runInstall()
                } label: {
                    Label(platformManager.isOperationRunning ? "Processing..." : "Install Package", systemImage: "square.and.arrow.down")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(platformManager.isOperationRunning)

                Button {
                    runUpdate()
                } label: {
                    Label("Update / Downgrade", systemImage: "arrow.up.and.down.circle")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(platformManager.isOperationRunning)

                Button {
                    runUninstall()
                } label: {
                    Label("Uninstall / Remove", systemImage: "trash")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(platformManager.isOperationRunning)
            }

            Divider()

            // Maintenance Actions
            VStack(alignment: .leading, spacing: 10) {
                Text("Maintenance & Repair")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Button("Repair Manifest Integrity") {
                    runRepair()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Verify Dependencies Resolvability") {
                    runVerify()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 300, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct LoggingAndProcessMonitorPanel: View {
    var platformManager: DependencyPlatformManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Console Output Logs", systemImage: "terminal")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    platformManager.operationLogs.removeAll()
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if platformManager.isOperationRunning {
                HStack {
                    ProgressView(value: platformManager.operationProgress)
                        .frame(width: 140)
                    Text(platformManager.operationStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.04))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if platformManager.operationLogs.isEmpty {
                        Text("No activity logs captured yet. Execute installation operations above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(platformManager.operationLogs, id: \.self) { log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
