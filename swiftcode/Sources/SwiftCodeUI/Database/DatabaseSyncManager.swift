import Combine
import Foundation
import SwiftCodeCloud

/// The difference between two schemas: tables (and columns)
/// present on one side and missing or changed on the other.
public struct DatabaseSchemaDiff: Sendable, Equatable {
    /// Tables present in the source and absent from the destination.
    public var tablesOnlyInSource: [DatabaseTable]
    /// Tables present in the destination and absent from the source.
    public var tablesOnlyInDestination: [DatabaseTable]
    /// Tables present on both sides whose columns differ, as
    /// (table name, columns only in source, columns only in
    /// destination, columns whose declared type differs).
    public var changedTables: [(tableName: String, addedColumns: [DatabaseColumn], removedColumns: [DatabaseColumn], changedColumns: [(source: DatabaseColumn, destination: DatabaseColumn)])]

    public var isEmpty: Bool {
        tablesOnlyInSource.isEmpty && tablesOnlyInDestination.isEmpty && changedTables.isEmpty
    }

    public init(
        tablesOnlyInSource: [DatabaseTable] = [],
        tablesOnlyInDestination: [DatabaseTable] = [],
        changedTables: [(tableName: String, addedColumns: [DatabaseColumn], removedColumns: [DatabaseColumn], changedColumns: [(source: DatabaseColumn, destination: DatabaseColumn)])] = []
    ) {
        self.tablesOnlyInSource = tablesOnlyInSource
        self.tablesOnlyInDestination = tablesOnlyInDestination
        self.changedTables = changedTables
    }

    public static func == (lhs: DatabaseSchemaDiff, rhs: DatabaseSchemaDiff) -> Bool {
        lhs.tablesOnlyInSource == rhs.tablesOnlyInSource
            && lhs.tablesOnlyInDestination == rhs.tablesOnlyInDestination
            && lhs.changedTables.map(\.tableName) == rhs.changedTables.map(\.tableName)
    }
}

/// Copies a source schema onto a destination connection.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Core/DatabaseSyncManager.swift`,
/// extended with the real schema diff Legacy never computed:
/// `diffSchemas(from:to:)` compares the two live schemas table by
/// table and column by column, and `synchronizeSchemas(from:to:)`
/// now applies only the missing-table half of that diff (creating
/// tables the destination lacks). Column-level differences are
/// reported in the diff and deliberately not auto-applied — there
/// is no `ALTER TABLE` path in `DatabaseSchemaManager`, and
/// silently rewriting a live table's columns would be data loss
/// dressed as a sync. Supabase reads go through the destination's
/// `SupabaseService` value type (`SupabaseService()` — no
/// `.shared`); providers with no driver in this package read as
/// an empty schema, exactly as Legacy read them.
@MainActor
public final class DatabaseSyncManager: ObservableObject {
    public static let shared = DatabaseSyncManager()

    @Published public var syncInProgress = false
    @Published public var lastSyncTimestamp: Date?
    @Published public var lastDiff: DatabaseSchemaDiff?

    private init() {}

    /// The live schema diff between two connections, computed from
    /// the tables each side actually has.
    public func diffSchemas(from source: DatabaseConnection, to destination: DatabaseConnection) async throws -> DatabaseSchemaDiff {
        let sourceTables = try await fetchTables(for: source)
        let destinationTables = try await fetchTables(for: destination)

        let sourceByName = Dictionary(uniqueKeysWithValues: sourceTables.map { ($0.name, $0) })
        let destinationByName = Dictionary(uniqueKeysWithValues: destinationTables.map { ($0.name, $0) })

        let tablesOnlyInSource = sourceTables.filter { destinationByName[$0.name] == nil }
        let tablesOnlyInDestination = destinationTables.filter { sourceByName[$0.name] == nil }

        var changedTables: [(tableName: String, addedColumns: [DatabaseColumn], removedColumns: [DatabaseColumn], changedColumns: [(source: DatabaseColumn, destination: DatabaseColumn)])] = []
        for sourceTable in sourceTables {
            guard let destinationTable = destinationByName[sourceTable.name] else { continue }
            let sourceColumns = Dictionary(uniqueKeysWithValues: sourceTable.columns.map { ($0.name, $0) })
            let destinationColumns = Dictionary(uniqueKeysWithValues: destinationTable.columns.map { ($0.name, $0) })
            let added = sourceTable.columns.filter { destinationColumns[$0.name] == nil }
            let removed = destinationTable.columns.filter { sourceColumns[$0.name] == nil }
            var changed: [(source: DatabaseColumn, destination: DatabaseColumn)] = []
            for sourceColumn in sourceTable.columns {
                if let destinationColumn = destinationColumns[sourceColumn.name],
                   destinationColumn.type != sourceColumn.type {
                    changed.append((source: sourceColumn, destination: destinationColumn))
                }
            }
            if !added.isEmpty || !removed.isEmpty || !changed.isEmpty {
                changedTables.append((tableName: sourceTable.name, addedColumns: added, removedColumns: removed, changedColumns: changed))
            }
        }

        return DatabaseSchemaDiff(
            tablesOnlyInSource: tablesOnlyInSource,
            tablesOnlyInDestination: tablesOnlyInDestination,
            changedTables: changedTables
        )
    }

    /// Creates, on the destination, every table the source has and
    /// the destination lacks. Column differences are reported in
    /// `lastDiff` and not auto-applied (see the type doc).
    public func synchronizeSchemas(from source: DatabaseConnection, to destination: DatabaseConnection) async throws {
        syncInProgress = true
        defer { syncInProgress = false }

        let diff = try await diffSchemas(from: source, to: destination)
        lastDiff = diff

        for table in diff.tablesOnlyInSource {
            try await DatabaseSchemaManager.shared.createTable(connection: destination, table: table)
        }

        lastSyncTimestamp = Date()
    }

    // MARK: - Private

    /// The live tables of a connection, by provider. SQLite reads
    /// through `DatabaseManager`; Supabase through
    /// `SupabaseService`; anything else has no driver and reads as
    /// an empty schema.
    private func fetchTables(for connection: DatabaseConnection) async throws -> [DatabaseTable] {
        switch connection.provider {
        case .sqlite:
            guard let filePath = connection.sqliteFilePath else { return [] }
            return try DatabaseManager.shared.fetchSQLiteTables(filePath: filePath)
        case .supabase:
            return try await SupabaseService().fetchTables(connection: connection)
        default:
            return []
        }
    }
}
