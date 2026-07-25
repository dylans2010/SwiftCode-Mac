import SwiftUI

public struct ICloudCloudView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessing = false
    @State private var statusMessage = ""

    private var backupManager: BackupManager {
        BackupManager.shared
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Apple iCloud Management")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !statusMessage.isEmpty {
                        GroupBox {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                Text(statusMessage)
                                Spacer()
                                Button("Dismiss") {
                                    statusMessage = ""
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(4)
                        }
                    }

                    // Account details
                    GroupBox(label: Label("iCloud Account Details", systemImage: "applelogo")) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("iCloud Status:")
                                Spacer()
                                if ICloudKitService.shared.accountStatus == .available {
                                    Text("Available")
                                        .foregroundStyle(.green)
                                        .bold()
                                } else {
                                    Text("Unavailable")
                                        .foregroundStyle(.red)
                                        .bold()
                                }
                            }

                            HStack {
                                Text("Connected Apple ID / User:")
                                Spacer()
                                Text(ICloudKitService.shared.currentAppleAccount ?? "No Account Signed In")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }

                    // Automated Backups & Restore
                    GroupBox(label: Label("iCloud Backups & Restoration", systemImage: "arrow.clockwise.icloud")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable CloudKit Automated Backups", isOn: Binding(
                                get: { backupManager.automaticBackupsEnabled },
                                set: { backupManager.automaticBackupsEnabled = $0 }
                            ))
                            .toggleStyle(.checkbox)

                            Text("When active, SwiftCode periodically saves complete point-in-time state records directly into your secure, private CloudKit container.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            HStack {
                                if isProcessing {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Button("Create Manual Backup") {
                                        executeBackupAction {
                                            try await backupManager.createBackup(name: "Manual iCloud Backup", provider: .icloud)
                                            statusMessage = "Manual iCloud backup completed successfully."
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Restore from Backup...") {
                                        if let lastBackup = backupManager.backups.first(where: { $0.providerType == .icloud }) {
                                            executeBackupAction {
                                                try await backupManager.restoreBackup(lastBackup.id)
                                                statusMessage = "iCloud backup restored successfully."
                                            }
                                        } else {
                                            statusMessage = "No iCloud backups found to restore."
                                        }
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Delete iCloud Backups") {
                                        for backup in backupManager.backups where backup.providerType == .icloud {
                                            backupManager.deleteBackup(backup.id)
                                        }
                                        statusMessage = "iCloud backups purged."
                                    }
                                    .buttonStyle(.bordered)
                                    .foregroundColor(.red)
                                }
                            }
                        }
                        .padding(8)
                    }

                    // Diagnostics & Health
                    GroupBox(label: Label("CloudKit Sync Diagnostics", systemImage: "waveform.path.ecg")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Container ID:")
                                Spacer()
                                Text("iCloud.com.SwiftCode.container")
                                    .font(.system(.caption, design: .monospaced))
                            }

                            HStack {
                                Text("Environment:")
                                Spacer()
                                Text("Production")
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Last Synced Zone:")
                                Spacer()
                                Text("SwiftCodeCustomSyncZone")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }
                .padding()
            }
        }
    }

    private func executeBackupAction(_ action: @escaping () async throws -> Void) {
        isProcessing = true
        statusMessage = ""
        Task {
            do {
                try await action()
                isProcessing = false
            } catch {
                statusMessage = "Operation failed: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
}
