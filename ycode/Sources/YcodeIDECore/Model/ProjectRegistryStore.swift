// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Persistence/ProjectRegistryStore.swift
// Adapted for Ycode: ProjectRegistryEntry + ProjectKind are declared here: Legacy defined them in Core/Project/ProjectRegistryEntry.swift and Core/Project/ProjectKind.swift (the Core slice). COORDINATOR NOTE: do not define them twice — if the Core slice lands its own copies, this file's declarations must be removed and the store must use theirs. PathTool replaced by FileManager's Application Support directory (PathTool had no definition in Legacy's Backend/Core/Models/Frameworks). The try! in Legacy's registryURL is gone: the URL is computed by a throwing helper.

import Foundation

/// The kind of a registered project root. Shape matches Legacy's
/// `Core/Project/ProjectKind.swift` exactly (same raw values), so registry
/// files written by Legacy still decode.
public enum ProjectKind: String, Codable, Sendable {
    case xcodeProject
    case swiftPackage
    case folder
}

/// One registered project root. Shape matches Legacy's
/// `Core/Project/ProjectRegistryEntry.swift` exactly.
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

/// The registry of known project roots, persisted as
/// `ProjectRegistry.json` in Application Support.
public actor ProjectRegistryStore {
    public static let shared = ProjectRegistryStore()

    private func registryURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ProjectRegistry.json")
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
