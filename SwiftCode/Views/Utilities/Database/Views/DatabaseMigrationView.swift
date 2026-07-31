import SwiftUI

struct DatabaseMigrationView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @StateObject private var migManager = DatabaseMigrationManager.shared

    @State private var name = ""
    @State private var sqlUp = "CREATE TABLE logs (\n    id INTEGER PRIMARY KEY,\n    message TEXT\n);"
    @State private var sqlDown = "DROP TABLE IF EXISTS logs;"
    @State private var resultMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left Panel: Create Migration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Generate New Migration")
                        .font(.headline)

                    TextField("Migration Name (e.g. add_logs_table)", text: $name)

                    Text("SQL Up (Apply)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $sqlUp)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Text("SQL Down (Rollback)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $sqlDown)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 100)
                        .border(Color.secondary.opacity(0.2))

                    Button("Generate Migration File") {
                        generateMigration()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || sqlUp.isEmpty || sqlDown.isEmpty)
                }
                .padding()
                .frame(width: 320)

                Divider()

                // Right Panel: Applied & Pending Migrations
                VStack(alignment: .leading, spacing: 12) {
                    Text("Migration History")
                        .font(.headline)

                    if migManager.migrations.isEmpty {
                        ContentUnavailableView("No migrations generated", systemImage: "arrow.triangle.2.circlepath", description: Text("Created migration scripts will appear here."))
                    } else {
                        List(migManager.migrations) { mig in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(mig.version)_\(mig.name)")
                                        .font(.subheadline.bold())
                                    Spacer()
                                    if let appliedAt = mig.appliedAt {
                                        Text("Applied (\(DatabaseFormatter.formatDate(appliedAt)))")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Pending")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }

                                HStack {
                                    if mig.appliedAt == nil {
                                        Button("Apply") {
                                            applyMigration(mig)
                                        }
                                        .buttonStyle(.bordered)
                                    } else {
                                        Button("Rollback") {
                                            rollbackMigration(mig)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }

            if !resultMessage.isEmpty {
                Divider()
                Text(resultMessage)
                    .foregroundColor(.blue)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
            }
        }
    }

    private func generateMigration() {
        _ = migManager.generateMigration(name: name, sqlUp: sqlUp, sqlDown: sqlDown)
        resultMessage = "Migration file generated successfully!"
        name = ""
    }

    private func applyMigration(_ mig: DatabaseMigration) {
        guard let conn = connManager.activeConnection else { return }
        Task {
            do {
                try await migManager.applyMigration(mig, on: conn)
                resultMessage = "Successfully applied migration \(mig.name)!"
            } catch {
                resultMessage = "Failed to apply: \(error.localizedDescription)"
            }
        }
    }

    private func rollbackMigration(_ mig: DatabaseMigration) {
        guard let conn = connManager.activeConnection else { return }
        Task {
            do {
                try await migManager.rollbackMigration(mig, on: conn)
                resultMessage = "Successfully rolled back migration \(mig.name)!"
            } catch {
                resultMessage = "Failed to rollback: \(error.localizedDescription)"
            }
        }
    }
}
