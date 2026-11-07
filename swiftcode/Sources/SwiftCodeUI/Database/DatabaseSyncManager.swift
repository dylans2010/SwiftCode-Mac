import Combine
import Foundation
import SwiftCodeCloud

public struct DatabaseSchemaDiff: Sendable, Equatable {
    public var tablesOnlyInSource: [DatabaseTable]
    public var tablesOnlyInDestination: [DatabaseTable]
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

@MainActor
public final class DatabaseSyncManager: ObservableObject {
    public static let shared = DatabaseSyncManager()

    @Published public var syncInProgress = false
    @Published public var lastSyncTimestamp: Date?
    @Published public var lastDiff: DatabaseSchemaDiff?

    private init() {}

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
