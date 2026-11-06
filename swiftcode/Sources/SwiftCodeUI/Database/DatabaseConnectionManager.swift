import Combine
import Foundation
import SwiftCodeCloud

/// The saved database connections, keyed by connection.
///
/// Ported verbatim from Legacy's
/// `Views/Utilities/Database/Core/DatabaseConnectionManager.swift`
/// with one deliberate storage change: Legacy persisted the
/// connection list in `UserDefaults` under
/// `com.swiftcode.database.connections`; this port persists it as
/// JSON in Application Support
/// (`SwiftCode/Databases/connections.json`), where a credential-
/// bearing record belongs, and migrates a Legacy `UserDefaults`
/// record into that file on first load. The default connection —
/// a local SQLite file at `SwiftCode/Databases/default.db` — is
/// created exactly as Legacy created it.
@MainActor
public final class DatabaseConnectionManager: ObservableObject {
    public static let shared = DatabaseConnectionManager()

    @Published public var connections: [DatabaseConnection] = []
    @Published public var activeConnection: DatabaseConnection?

    /// The directory that holds the default database file and the
    /// persisted connection list.
    public static var databasesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SwiftCode/Databases", isDirectory: true)
    }

    /// Legacy `UserDefaults` key, read once to migrate connections
    /// saved by the Legacy app. Never written by this port.
    private static let legacyUserDefaultsKey = "com.swiftcode.database.connections"

    private var connectionsFileURL: URL {
        Self.databasesDirectory.appendingPathComponent("connections.json")
    }

    private init() {
        loadConnections()
        if connections.isEmpty {
            createDefaultSQLiteConnection()
        }
        activeConnection = connections.first
    }

    public func addConnection(_ conn: DatabaseConnection) {
        connections.append(conn)
        saveConnections()
    }

    public func removeConnection(_ conn: DatabaseConnection) {
        connections.removeAll { $0.id == conn.id }
        if activeConnection?.id == conn.id {
            activeConnection = connections.first
        }
        saveConnections()
    }

    public func updateConnection(_ conn: DatabaseConnection) {
        if let index = connections.firstIndex(where: { $0.id == conn.id }) {
            connections[index] = conn
            if activeConnection?.id == conn.id {
                activeConnection = conn
            }
            saveConnections()
        }
    }

    private func createDefaultSQLiteConnection() {
        let dbFile = Self.databasesDirectory.appendingPathComponent("default.db").path

        let defaultConn = DatabaseConnection(
            name: "Default Local SQLite",
            provider: .sqlite,
            sqliteFilePath: dbFile
        )
        connections.append(defaultConn)
        saveConnections()
    }

    private func loadConnections() {
        if let data = try? Data(contentsOf: connectionsFileURL),
           let decoded = try? JSONDecoder().decode([DatabaseConnection].self, from: data) {
            self.connections = decoded
            return
        }
        // One-time migration from Legacy's UserDefaults storage.
        if let data = UserDefaults.standard.data(forKey: Self.legacyUserDefaultsKey),
           let decoded = try? JSONDecoder().decode([DatabaseConnection].self, from: data) {
            self.connections = decoded
            saveConnections()
            UserDefaults.standard.removeObject(forKey: Self.legacyUserDefaultsKey)
        }
    }

    private func saveConnections() {
        do {
            try FileManager.default.createDirectory(
                at: Self.databasesDirectory, withIntermediateDirectories: true, attributes: nil)
            let encoded = try JSONEncoder().encode(connections)
            try encoded.write(to: connectionsFileURL, options: .atomic)
        } catch {
            // Persistence is best-effort: the in-memory list stays
            // authoritative for this session, and the next launch
            // re-reads whatever did land on disk.
        }
    }
}
