import Foundation

@MainActor
public final class DatabaseMigrationManager: ObservableObject {
    public static let shared = DatabaseMigrationManager()

    @Published public var migrations: [DatabaseMigration] = []

    private init() {
        loadMigrations()
    }

    public func generateMigration(name: String, sqlUp: String, sqlDown: String) -> DatabaseMigration {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        let version = formatter.string(from: Date())

        let migration = DatabaseMigration(
            version: version,
            name: name,
            sqlUp: sqlUp,
            sqlDown: sqlDown
        )

        migrations.append(migration)
        saveMigrations()
        return migration
    }

    public func applyMigration(_ migration: DatabaseMigration, on connection: DatabaseConnection) async throws {
        switch connection.provider {
        case .sqlite:
            guard let filePath = connection.sqliteFilePath else { return }
            _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: filePath, sql: migration.sqlUp)
        case .supabase:
            _ = try await SupabaseService.shared.executeSQL(connection: connection, sql: migration.sqlUp)
        default:
            break
        }

        if let idx = migrations.firstIndex(where: { $0.id == migration.id }) {
            migrations[idx].appliedAt = Date()
            saveMigrations()
        }
    }

    public func rollbackMigration(_ migration: DatabaseMigration, on connection: DatabaseConnection) async throws {
        switch connection.provider {
        case .sqlite:
            guard let filePath = connection.sqliteFilePath else { return }
            _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: filePath, sql: migration.sqlDown)
        case .supabase:
            _ = try await SupabaseService.shared.executeSQL(connection: connection, sql: migration.sqlDown)
        default:
            break
        }

        if let idx = migrations.firstIndex(where: { $0.id == migration.id }) {
            migrations[idx].appliedAt = nil
            saveMigrations()
        }
    }

    private func loadMigrations() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.database.migrations"),
           let decoded = try? JSONDecoder().decode([DatabaseMigration].self, from: data) {
            self.migrations = decoded
        }
    }

    private func saveMigrations() {
        if let encoded = try? JSONEncoder().encode(migrations) {
            UserDefaults.standard.set(encoded, forKey: "com.swiftcode.database.migrations")
        }
    }
}
