import SwiftUI

struct DatabaseBackupView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @StateObject private var backupManager = DatabaseBackupManager.shared
    @State private var message = ""

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
                }
                .padding(8)
            }
            .padding()

            Divider()

            // Backups List
            List(backupManager.backupPaths, id: \.self) { path in
                HStack {
                    Image(systemName: "archivebox.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.subheadline.bold())
                        Text(path)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Restore") {
                        triggerRestore(path)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
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
    }

    private func triggerBackup() {
        guard let conn = connManager.activeConnection else { return }
        do {
            let path = try backupManager.createBackup(connection: conn)
            message = "Backup created successfully at:\n\(path)"
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }

    private func triggerRestore(_ path: String) {
        guard let conn = connManager.activeConnection else { return }
        do {
            try backupManager.restoreBackup(path, to: conn)
            message = "Database successfully restored to snapshot!"
        } catch {
            message = "Failed: \(error.localizedDescription)"
        }
    }
}
