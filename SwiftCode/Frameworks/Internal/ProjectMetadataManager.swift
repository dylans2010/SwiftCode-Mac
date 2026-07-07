import Foundation

public struct ProjectMetadata: Codable, Sendable {
    public var name: String
    public var description: String?
    public var author: String?
    public var version: String
    public var createdAt: Date
    public var updatedAt: Date
}

public final class ProjectMetadataManager {
    public static let shared = ProjectMetadataManager()
    private init() {}

    public func generateMetadata(for project: Project) -> ProjectMetadata {
        return ProjectMetadata(
            name: project.name,
            description: project.description,
            author: "User",
            version: "1.0.0",
            createdAt: project.createdAt,
            updatedAt: Date()
        )
    }
}
