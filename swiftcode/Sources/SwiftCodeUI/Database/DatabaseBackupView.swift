// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Utilities/Database/Views/DatabaseBackupView.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeUI/Database/DatabaseBackupView.swift.
//
// Adaptations (behaviour preserved unless noted) — the destination backup
// manager's API differs from Legacy's, so the view is re-wired, not copied:
// * Legacy: `DatabaseBackupManager.shared` (ObservableObject) with
//   `backupPaths: [String]`, `createBackup(connection:) -> String` and
//   `restoreBackup(path, to:)`.
//   Destination (`SwiftCodeIDECore/Model/Database/DatabaseBackups.swift`):
//   no `shared`, not an ObservableObject — `init(databasePath:
//   backupDirectory:)`, `createBackup(date:) -> DatabaseBackup`,
//   `listBackups() -> [DatabaseBackup]`, `restore(_:)`, and the backup
//   directory (not a UserDefaults registry) is the source of truth.
//   The view therefore builds the manager from the active connection's
//   `sqliteFilePath`, keeps the backup list in `@State`, and refreshes it
//   after every create/restore and whenever the active connection changes.
// * Backups are SQLite-file copies, so the view is only meaningful for a
//   SQLite active connection: with no active connection, or a network
//   (Postgres/MySQL/Supabase) one, it says so instead of offering a
//   backup button for a file that does not exist.
// * `.groupBoxStyle(.liquidGlass)` has no destination equivalent —
//   SwiftCode draws no glass of its own making — so the card uses
//   `.groupBoxStyle(ModernGroupBoxStyle())` (this target).
// * Restore caveat, inherited from the destination manager's contract:
//   restoring copies the backup back over the database file, so any open
//   connection to that database must be closed first; the explorer
//   window closes and reopens the model around a restore
//   (DatabaseBackups.swift header). This view reports the restore result
//   and does not itself reopen the connection.
// * `import SwiftCodeIDECore` added for the backup types (SwiftCodeUI
//   already depends on SwiftCodeIDECore).

import SwiftUI
import SwiftCodeIDECore

struct DatabaseBackupView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var backups: [DatabaseBackup] = []
    @State private var message = ""

    /// The manager for the active SQLite connection, if there is one.
    private var backupManager: DatabaseBackupManager? {
        guard let path = connManager.activeConnection?.sqliteFilePath else { return nil }
        return DatabaseBackupManager(databasePath: path)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Take Backup Card
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

            // Backups List
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
