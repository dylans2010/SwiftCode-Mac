import Combine
import Foundation
import SwiftCodeCloud

@MainActor
public final class DatabaseConnectionManager: ObservableObject {
    public static let shared = DatabaseConnectionManager()

    @Published public var connections: [DatabaseConnection] = []
    @Published public var activeConnection: DatabaseConnection?

    public static var databasesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SwiftCode/Databases", isDirectory: true)
    }

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
        }
    }
}
