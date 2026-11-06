import Foundation

// MARK: - Package Dependency

public struct PackageDependency: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var url: String
    public var version: String
    public var source: DependencySource

    public init(id: UUID = UUID(), name: String, url: String, version: String, source: DependencySource) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
        self.source = source
    }

    public enum DependencySource: String, Codable, CaseIterable, Sendable {
        case github = "GitHub"
        case swiftPackageIndex = "Swift Package Index"
        case gitURL = "Git URL"
    }

    public var packageSwiftEntry: String {
        ".package(url: \"\(url)\", from: \"\(version)\")"
    }
}
