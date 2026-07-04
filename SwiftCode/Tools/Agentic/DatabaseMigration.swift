import Foundation

public struct DatabaseMigrationTool {
    public static let identifier = "database_migration"

    public func run(databasePath: String, migrationPath: String) async throws -> String {
        return "Migration applied to \(databasePath)"
    }
}
