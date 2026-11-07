import Foundation

public final class ProjectMetadataManager: Sendable {
    public static let shared = ProjectMetadataManager()
    private init() {}

    @MainActor
    public func generateMetadata(for project: Project) -> ProjectMetadata {
        return ProjectMetadata(
            name: project.name,
            description: project.description,
            author: AppSettings.shared.fileHeaderAuthor,
            version: "1.0.0",
            createdAt: project.createdAt,
            updatedAt: Date()
        )
    }
}
