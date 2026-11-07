import SwiftUI
import SwiftCodeIDECore

struct DatabaseBackupView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var backups: [DatabaseBackup] = []
    @State private var message = ""

    private var backupManager: DatabaseBackupManager? {
        guard let path = connManager.activeConnection?.sqliteFilePath else { return nil }
        return DatabaseBackupManager(databasePath: path)
    }

    var body: some View {
        VStack(spacing: 0) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Take Database Backup Snapshot")
                        .font(.headline)
                    Text("This creates a perfect physical zip or binary replica of the active SQLite database file stored securely on disk.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("Create Backup Now") {
                        triggerBackup()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(backupManager == nil)
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())
            .padding()

            Divider()

            if backupManager == nil {
                Text("Backups need an active SQLite connection. Connect a local SQLite file to create and restore snapshots.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(backups) { backup in
                    HStack {
                        Image(systemName: "archivebox.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading) {
                            Text(backup.url.lastPathComponent)
                                .font(.subheadline.bold())
                            Text(backup.url.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Restore") {
                            triggerRestore(backup)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !message.isEmpty {
                Divider()
                Text(message)
                    .foregroundColor(.blue)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
            }
        }
        .onAppear {
            refreshBackups()
        }
        .onChange(of: connManager.activeConnection?.id) {
            refreshBackups()
        }
    }

    private func refreshBackups() {
        backups = backupManager?.listBackups() ?? []
    }

    private func triggerBackup() {
        guard let manager = backupManager else { return }
        do {
            let backup = try manager.createBackup()
            message = "Backup created successfully at:\n\(backup.url.path)"
            refreshBackups()
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }

    private func triggerRestore(_ backup: DatabaseBackup) {
        guard let manager = backupManager else { return }
        do {
            try manager.restore(backup)
            message = "Database successfully restored to snapshot!"
            refreshBackups()
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }
}
