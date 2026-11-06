import Foundation

/// Disk persistence for the local cloud cache, ported from Legacy's
/// `CloudPersistence.swift` (46 lines) with one deliberate change:
/// the cache file keeps Legacy's path
/// (`Application Support/SwiftCode/CloudCache/cloud_cache.json`) so
/// an existing Legacy install's cached records survive the move —
/// the directory name is the product's, not the old host's.
///
/// Only `CloudRecord` values are ever written here — never sessions,
/// secrets, or credentials.
public final class CloudPersistence: Sendable {
    public static let shared = CloudPersistence()

    private init() {}

    private var cacheFileURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let root = paths[0].appendingPathComponent("SwiftCode/CloudCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("cloud_cache.json")
    }

    public func saveToDisk(records: [CloudRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            // Legacy logged the failure and continued; there is no
            // logger in this target, so a failed cache write is
            // silent — the in-memory cache is still authoritative.
        }
    }

    public func loadFromDisk() -> [CloudRecord] {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: cacheFileURL)
            return try JSONDecoder().decode([CloudRecord].self, from: data)
        } catch {
            return []
        }
    }

    public func clearCacheOnDisk() {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
}
