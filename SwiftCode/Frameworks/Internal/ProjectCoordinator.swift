import Foundation

public final class ProjectCoordinator {
    public static let shared = ProjectCoordinator()
    private init() {}

    public func exportProject(_ project: Project, to destinationURL: URL) async throws {
        try await ProjectSerializer.shared.serialize(project: project, to: destinationURL)
    }

    public func importProject(from packageURL: URL) async throws -> Project {
        return try ProjectDeserializer.shared.deserialize(from: packageURL)
    }

    public func validateProject(at packageURL: URL) throws {
        try ProjectValidator.shared.validate(packageURL: packageURL)
    }

    public func getManifest(for packageURL: URL) throws -> ProjectManifest {
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let data = try ProjectFileManager.shared.readFile(at: manifestURL)
        return try ProjectJSONManager.shared.decode(ProjectManifest.self, from: data)
    }
}
