import Foundation
import SwiftCodeCloud

/// In-memory cache of fetched schemas, keyed by connection.
///
/// Ported verbatim from Legacy's
/// `Views/Utilities/Database/Core/DatabaseCache.swift`.
/// Main-actor isolated: the cache is a plain dictionary and the
/// managers that read it (`DatabaseManager`, `DatabaseSyncManager`)
/// already run on the main actor.
@MainActor
public final class DatabaseCache {
    public static let shared = DatabaseCache()

    private var tableCache: [String: [DatabaseTable]] = [:]

    private init() {}

    public func cacheTables(_ tables: [DatabaseTable], for connectionID: UUID) {
        tableCache[connectionID.uuidString] = tables
    }

    public func getCachedTables(for connectionID: UUID) -> [DatabaseTable]? {
        return tableCache[connectionID.uuidString]
    }

    public func invalidateCache(for connectionID: UUID) {
        tableCache.removeValue(forKey: connectionID.uuidString)
    }

    public func clearAll() {
        tableCache.removeAll()
    }
}
