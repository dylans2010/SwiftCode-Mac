import Foundation

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
