import SwiftUI
import SwiftCodeCloud

@MainActor
struct DatabaseConnectionsView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var testingID: UUID?
    @State private var testResult: [UUID: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Database Connections")
                    .font(.title2.bold())

                ForEach(connManager.connections) { conn in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(conn.name, systemImage: "cylinder.split.1x2.fill")
                                    .font(.headline)
                                Spacer()
                                Text(conn.provider.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                            }

                            if conn.provider == .sqlite {
                                Text("File Path: \(conn.sqliteFilePath ?? "None")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Host: \(conn.host ?? "localhost"):\(conn.port ?? 5432)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Button("Test Connection") {
                                    testConnection(conn)
                                }
                                .disabled(testingID == conn.id)

                                if let result = testResult[conn.id] {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundColor(result.contains("Successful") ? .green : .red)
                                }

                                Spacer()

                                if connManager.activeConnection?.id != conn.id {
                                    Button("Make Active") {
                                        connManager.activeConnection = conn
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Button("Delete") {
                                    connManager.removeConnection(conn)
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding()
        }
    }

    private func testConnection(_ conn: DatabaseConnection) {
        testingID = conn.id
        Task { @MainActor in
            do {
                if conn.provider == .sqlite {
                    let existed = conn.sqliteFilePath.map { FileManager.default.fileExists(atPath: $0) } ?? false
                    let explorer = try DatabaseViewSQLite.explorerCreatingFileIfNeeded(for: conn)
                    _ = try explorer.run(sql: "SELECT 1;")
                    testResult[conn.id] = existed
                        ? "Connection Successful!"
                        : "Connection Successful! (Created DB file)"
                } else if conn.provider == .supabase {
                    let success = try await SupabaseService().testConnection(connection: conn)
                    testResult[conn.id] = success ? "Connection Successful!" : "Failed to connect."
                } else {
                    testResult[conn.id] = "No live test for \(conn.provider.rawValue) — details recorded."
                }
            } catch {
                testResult[conn.id] = "Failed: \(error.localizedDescription)"
            }
            testingID = nil
        }
    }
}
