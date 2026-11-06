import Foundation

@MainActor
public final class DatabaseConnectionManager: ObservableObject {
    public static let shared = DatabaseConnectionManager()

    @Published public var connections: [DatabaseConnection] = []
    @Published public var activeConnection: DatabaseConnection?

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
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbFolder = appSupport.appendingPathComponent("SwiftCode/Databases", isDirectory: true)
        let dbFile = dbFolder.appendingPathComponent("default.db").path

        let defaultConn = DatabaseConnection(
            name: "Default Local SQLite",
            provider: .sqlite,
            sqliteFilePath: dbFile
        )
        connections.append(defaultConn)
        saveConnections()
    }

    private func loadConnections() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.database.connections"),
           let decoded = try? JSONDecoder().decode([DatabaseConnection].self, from: data) {
            self.connections = decoded
        }
    }

    private func saveConnections() {
        if let encoded = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(encoded, forKey: "com.swiftcode.database.connections")
        }
    }
}
