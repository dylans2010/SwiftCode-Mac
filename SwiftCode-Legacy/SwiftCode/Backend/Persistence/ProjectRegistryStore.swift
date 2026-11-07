import Foundation

public actor ProjectRegistryStore {
    public static let shared = ProjectRegistryStore()

    private var registryURL: URL {
        try! PathTool.appSupportDirectory().appendingPathComponent("ProjectRegistry.json")
    }

    public func load() throws -> [ProjectRegistryEntry] {
        guard FileManager.default.fileExists(atPath: registryURL.path) else { return [] }
        let data = try Data(contentsOf: registryURL)
        return try JSONDecoder().decode([ProjectRegistryEntry].self, from: data)
    }

    public func save(_ entries: [ProjectRegistryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: registryURL)
    }
}
