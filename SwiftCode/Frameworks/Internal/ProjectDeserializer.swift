import Foundation

public final class ProjectDeserializer {
    public static let shared = ProjectDeserializer()
    private init() {}

    public func deserialize(from packageURL: URL) throws -> Project {
        // 1. Validate package
        try ProjectValidator.shared.validate(packageURL: packageURL)

        // 2. Read project.json
        let projectURL = packageURL.appendingPathComponent("project.json")
        let projectData = try ProjectFileManager.shared.readFile(at: projectURL)
        var project = try ProjectJSONManager.shared.decode(Project.self, from: projectData)

        // 3. Read manifest.json (and potentially migrate)
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifestData = try ProjectFileManager.shared.readFile(at: manifestURL)
        var manifest = try ProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)

        try ProjectVersionManager.shared.migrateIfNeeded(&manifest)

        // 4. Align Project model with Manifest data if necessary
        project.name = manifest.identity.name
        project.description = manifest.identity.description ?? ""
        project.createdAt = manifest.identity.createdAt
        project.lastOpened = Date()

        return project
    }
}
