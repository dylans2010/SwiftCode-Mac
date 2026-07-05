import SwiftUI

struct PermissionConfigView: View {
    @Binding var permission: TransferPermission

    var body: some View {
        Form {
            Section("Presets") {
                Picker("Access Level", selection: Binding(get: { permission.preset }, set: { permission = .makePreset($0) })) {
                    ForEach(TransferPermission.AccessPreset.allCases) { preset in
                        Text(preset.rawValue.capitalized).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Collaborative Project", isOn: $permission.isCollaborative)
                    .tint(.orange)
            }

            Section("File Operations") {
                permissionToggle("View Files", value: $permission.fileSystem.viewFiles)
                permissionToggle("Edit Files", value: $permission.fileSystem.editFiles)
                permissionToggle("Create Files", value: $permission.fileSystem.createFiles)
                permissionToggle("Delete Files", value: $permission.fileSystem.deleteFiles)
                permissionToggle("Rename Files", value: $permission.fileSystem.renameFiles)
                permissionToggle("Move Files", value: $permission.fileSystem.moveFiles)
                permissionToggle("Bulk Actions", value: $permission.fileSystem.bulkOperations)
            }

            Section("Project Settings") {
                permissionToggle("Modify Settings", value: $permission.projectManagement.modifyProjectSettings)
                permissionToggle("Edit Metadata", value: $permission.projectManagement.editMetadata)
                permissionToggle("Manage Dependencies", value: $permission.projectManagement.manageDependencies)
                permissionToggle("Environment Configs", value: $permission.projectManagement.editEnvironmentConfigs)
            }

            Section("Version Control") {
                permissionToggle("Commit", value: $permission.versionControl.commit)
                permissionToggle("Push", value: $permission.versionControl.push)
                permissionToggle("Pull", value: $permission.versionControl.pull)
                permissionToggle("Create/Delete Branches", value: $permission.versionControl.branchCreateDelete)
                permissionToggle("Revert Changes", value: $permission.versionControl.revert)
            }

            Section("Execution") {
                permissionToggle("Build Project", value: $permission.execution.buildProject)
                permissionToggle("Run Project", value: $permission.execution.runProject)
                permissionToggle("Execute Scripts", value: $permission.execution.executeScripts)
                permissionToggle("Terminal Access", value: $permission.execution.terminalAccess)
                permissionToggle("Background Tasks", value: $permission.execution.backgroundProcesses)
            }

            Section("Plugins & Extensions") {
                permissionToggle("Install Plugins", value: $permission.plugin.installPlugins)
                permissionToggle("Remove Plugins", value: $permission.plugin.removePlugins)
                permissionToggle("Execute Plugins", value: $permission.plugin.runPlugins)
                permissionToggle("Modify Files", value: $permission.plugin.allowPluginFileModification)
            }

            Section("Agent Permissions") {
                permissionToggle("Allow Agent Access", value: $permission.agent.allowAgentAccess)
                permissionToggle("File Modification", value: $permission.agent.allowAgentFileModification)
                permissionToggle("Code Generation", value: $permission.agent.allowAgentCodeGeneration)
                permissionToggle("Run Commands", value: $permission.agent.allowAgentToRunCommands)
                permissionToggle("Initiate Transfers", value: $permission.agent.allowAgentToInitiateTransfers)
            }

            Section("Transfer Control") {
                permissionToggle("Allow Re-transfer", value: $permission.transferControl.allowRetransfer)
                permissionToggle("Restrict to Sender", value: $permission.transferControl.restrictToOriginalSender)
                permissionToggle("One-time Access", value: $permission.transferControl.oneTimeAccessMode)

                DatePicker("Expiration", selection: Binding(
                    get: { permission.transferControl.expirationDate ?? Date().addingTimeInterval(3600 * 24) },
                    set: { permission.transferControl.expirationDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
            }

            Section("Security Restrictions") {
                permissionToggle("Hidden Files", value: $permission.security.hiddenFiles)
                permissionToggle("Encrypted Storage", value: $permission.security.encryptedStorage)
            }

            Section("Activity Logs") {
                permissionToggle("Track Edits", value: $permission.audit.trackEdits)
                permissionToggle("Track Deletions", value: $permission.audit.trackDeletions)
                permissionToggle("Track Executions", value: $permission.audit.trackExecutions)
                permissionToggle("Allow Review", value: $permission.audit.allowAuditReview)
            }

            if permission.agent.allowAgentToRunCommands || permission.versionControl.push {
                Label("High risk permissions enabled", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func permissionToggle(_ title: String, value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
    }
}
