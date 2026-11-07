import Foundation

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
