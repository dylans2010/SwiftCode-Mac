import Foundation

public final class ProjectVersionManager: Sendable {
    public static let shared = ProjectVersionManager()
    private init() {}

    public let currentSchemaVersion = 1

    public func checkCompatibility(manifest: ProjectManifest) -> Bool {
        return manifest.versioning.schemaVersion <= currentSchemaVersion
    }

    public func migrateIfNeeded(_ manifest: inout ProjectManifest) throws {
        while manifest.versioning.schemaVersion < currentSchemaVersion {
            try migrateToNextVersion(&manifest)
        }
    }

    private func migrateToNextVersion(_ manifest: inout ProjectManifest) throws {
        let fromVersion = manifest.versioning.schemaVersion
        let toVersion = fromVersion + 1

        // Migration logic here

        manifest.versioning.schemaVersion = toVersion
        manifest.versioning.migrationHistory.append(
            ProjectManifest.Versioning.MigrationEntry(
                fromVersion: fromVersion,
                toVersion: toVersion,
                date: Date(),
                description: "Migrated to version \(toVersion)"
            )
        )
    }
}
