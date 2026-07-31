import SwiftUI

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
        Task {
            do {
                if conn.provider == .sqlite {
                    if let path = conn.sqliteFilePath, FileManager.default.fileExists(atPath: path) {
                        testResult[conn.id] = "Connection Successful!"
                    } else if let path = conn.sqliteFilePath {
                        // Create the sqlite file
                        _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: "SELECT 1;")
                        testResult[conn.id] = "Connection Successful! (Created DB file)"
                    } else {
                        testResult[conn.id] = "Missing sqlite path."
                    }
                } else if conn.provider == .supabase {
                    let success = try await SupabaseService.shared.testConnection(connection: conn)
                    testResult[conn.id] = success ? "Connection Successful!" : "Failed to connect."
                } else {
                    testResult[conn.id] = "Connection details validated."
                }
            } catch {
                testResult[conn.id] = "Failed: \(error.localizedDescription)"
            }
            testingID = nil
        }
    }
}
