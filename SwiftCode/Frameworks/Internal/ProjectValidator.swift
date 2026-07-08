import Foundation

public final class ProjectValidator: Sendable {
    public static let shared = ProjectValidator()
    private init() {}

    public func validate(packageURL: URL) throws {
        // 1. Validate package structure
        guard ProjectPackageManager.shared.validatePackageStructure(at: packageURL) else {
            throw ProjectErrorManager.ProjectError.corruptedPackage("Invalid directory structure")
        }

        // 2. Load and validate manifest
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        guard ProjectFileManager.shared.exists(at: manifestURL) else {
            throw ProjectErrorManager.ProjectError.manifestMissing
        }

        let manifestData = try ProjectFileManager.shared.readFile(at: manifestURL)
        let manifest = try ProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)
        try ManifestProjManager.shared.validateManifest(manifest)

        // 3. Check version compatibility
        guard ProjectVersionManager.shared.checkCompatibility(manifest: manifest) else {
            throw ProjectErrorManager.ProjectError.versionIncompatible(ProjectVersionManager.shared.currentSchemaVersion, manifest.versioning.schemaVersion)
        }

        // 4. Verify integrity
        guard try ProjectIntegrityManager.shared.verifyIntegrity(at: packageURL, manifest: manifest) else {
            throw ProjectErrorManager.ProjectError.securityFailure("Integrity check failed")
        }

        // 5. Validate resources
        try ProjectResourceManager.shared.validateResources(at: packageURL)
    }
}
