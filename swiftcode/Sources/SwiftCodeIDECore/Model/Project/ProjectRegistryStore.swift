import Foundation

public enum ProjectKind: String, Codable, Sendable {
    case xcodeProject
    case swiftPackage
    case folder
}

public struct ProjectRegistryEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let rootURL: URL
    public let kind: ProjectKind
    public var lastOpenedAt: Date
    public var sourceControlEnabled: Bool

    public init(id: UUID = UUID(), name: String, rootURL: URL, kind: ProjectKind, lastOpenedAt: Date = Date(), sourceControlEnabled: Bool = false) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.kind = kind
        self.lastOpenedAt = lastOpenedAt
        self.sourceControlEnabled = sourceControlEnabled
    }
}

public actor ProjectRegistryStore {
    public static let shared = ProjectRegistryStore()

    private func registryURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ProjectRegistry.json")
    }

    public func note(rootURL: URL, name: String, kind: ProjectKind) async throws {
        var entries = (try? load()) ?? []
        if let index = entries.firstIndex(where: { $0.rootURL == rootURL }) {
            entries[index].lastOpenedAt = Date()
            let updated = entries.remove(at: index)
            entries.insert(updated, at: 0)
        } else {
            entries.insert(ProjectRegistryEntry(name: name, rootURL: rootURL, kind: kind), at: 0)
        }
        try save(entries)
    }

    public func load() throws -> [ProjectRegistryEntry] {
        let url = try registryURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ProjectRegistryEntry].self, from: data)
    }

    public func save(_ entries: [ProjectRegistryEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: registryURL())
    }
}
