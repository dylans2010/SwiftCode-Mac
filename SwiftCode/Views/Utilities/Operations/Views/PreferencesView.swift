import SwiftUI

struct PreferencesView: View {
    @State private var scanOnLaunch = true
    @State private var alertOnPackageUpdate = true
    @State private var enableTelemetry = true
    @State private var maxArchiveCount = 10

    // Session states
    @State private var sessionManager = WorkspaceSessionManager.shared
    @State private var newSessionName = ""

    // Automation states
    @State private var automation = AutomationEngine.shared
    @State private var newWorkflowName = ""
    @State private var selectedTrigger = "Project Opened"
    @State private var selectedActions: [String] = []

    private let triggerOptions = [
        "Project Opened", "Build Finished", "Device Connected",
        "VM Started", "Archive Exported", "Diagnostics Completed", "Backup Completed"
    ]

    private let actionOptions = [
        "Start VM", "Open Terminal", "Run npm install",
        "Run backend", "Launch browser", "Start AI assistant"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Operations Preferences & Workflows")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configure automated scans, save/restore sessions, and manage workflow automations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                // 1. General Preferences
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Automated Actions")
                            .font(.headline)

                        Toggle("Run full diagnostics integrity scan at window launch", isOn: $scanOnLaunch)
                        Toggle("Alert immediately when dependency package update is discovered", isOn: $alertOnPackageUpdate)
                        Toggle("Send anonymous crash/performance telemetry", isOn: $enableTelemetry)

                        Divider()

                        Stepper("Maximum retained archives in local registry: \(maxArchiveCount)", value: $maxArchiveCount, in: 5...30)
                        Text("When limit is reached, older archives are automatically compressed to zip and moved to backups directory.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. Workspace Session Snapshotting
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Workspace Session Manager")
                            .font(.headline)
                        Text("Capture and restore entire workspace states, including open projects, tabs, running VMs, and terminal configurations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Snapshot Name (e.g. Morning Backend Session)", text: $newSessionName)
                                .textFieldStyle(.roundedBorder)

                            Button("Capture Session") {
                                captureSession()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newSessionName.isEmpty)
                        }
                        .padding(.vertical, 4)

                        if sessionManager.savedSessions.isEmpty {
                            Text("No saved sessions. Capture current layout above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(sessionManager.savedSessions) { session in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(session.name)
                                                .fontWeight(.semibold)
                                            Text("Saved: \(formatDate(session.date)) • Projects: \(session.openProjectIDs.count) • Tabs: \(session.openTabs.count) • Running VMs: \(session.runningVMIDs.count)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Restore") {
                                            sessionManager.restoreSession(session)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            sessionManager.deleteSession(session)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3. Workflow Automation Engine
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Development Workflow Automation")
                            .font(.headline)
                        Text("Configure triggers to execute action sequences automatically when specific system events occur.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Create Workflow Subform
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Create Automated Workflow")
                                .font(.subheadline)
                                .fontWeight(.bold)

                            HStack {
                                TextField("Workflow Name (e.g., Bootstrap VM)", text: $newWorkflowName)
                                    .textFieldStyle(.roundedBorder)

                                Picker("Trigger:", selection: $selectedTrigger) {
                                    ForEach(triggerOptions, id: \.self) { opt in
                                        Text(opt).tag(opt)
                                    }
                                }
                                .frame(width: 250)
                            }

                            // Actions Multi-select checkboxes
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Select Action Sequences:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    ForEach(actionOptions, id: \.self) { action in
                                        HStack {
                                            Image(systemName: selectedActions.contains(action) ? "checkmark.square" : "square")
                                                .foregroundStyle(selectedActions.contains(action) ? .blue : .secondary)
                                            Text(action)
                                                .font(.caption)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if selectedActions.contains(action) {
                                                selectedActions.removeAll { $0 == action }
                                            } else {
                                                selectedActions.append(action)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(6)

                            Button("Add Workflow") {
                                createWorkflow()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newWorkflowName.isEmpty || selectedActions.isEmpty)
                        }
                        .padding(.vertical, 8)

                        Divider()

                        // Existing workflows list
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active Automation Workflows")
                                .font(.subheadline)
                                .fontWeight(.bold)

                            if automation.workflows.isEmpty {
                                Text("No active workflows configured.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach($automation.workflows) { $wf in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(wf.name)
                                                .fontWeight(.bold)
                                            Text("Trigger: \(wf.trigger) • Actions: \(wf.actions.joined(separator: " → "))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()

                                        Toggle("", isOn: $wf.isActive)
                                            .toggleStyle(.switch)
                                            .onChange(of: wf.isActive) { _, _ in
                                                automation.saveWorkflows()
                                            }

                                        Button {
                                            automation.deleteWorkflow(wf)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
    }

    private func captureSession() {
        let name = newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        sessionManager.snapshotCurrentSession(name: name)
        newSessionName = ""
    }

    private func createWorkflow() {
        let name = newWorkflowName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty && !selectedActions.isEmpty else { return }
        automation.addWorkflow(name: name, trigger: selectedTrigger, actions: selectedActions)
        newWorkflowName = ""
        selectedActions.removeAll()
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}
