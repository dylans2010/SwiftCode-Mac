import Foundation

public final class ProjectDeserializer: Sendable {
    public static let shared = ProjectDeserializer()
    private init() {}

    public func deserialize(from packageURL: URL) throws -> Project {
        try ProjectValidator.shared.validate(packageURL: packageURL)

        let projectURL = packageURL.appendingPathComponent("project.json")
        let projectData = try ProjectFileManager.shared.readFile(at: projectURL)
        var project = try ProjectJSONManager.shared.decode(Project.self, from: projectData)

        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifestData = try ProjectFileManager.shared.readFile(at: manifestURL)
        var manifest = try ProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)

        try ProjectVersionManager.shared.migrateIfNeeded(&manifest)

        project.name = manifest.identity.name
        project.description = manifest.identity.description ?? ""
        project.createdAt = manifest.identity.createdAt
        project.lastOpened = Date()

        return project
    }
}
