import Foundation
import ZIPFoundation

public final class ProjectValidator: Sendable {
    public static let shared = ProjectValidator()
    private init() {}

    public func validate(packageURL: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let fileExists = fm.fileExists(atPath: packageURL.path, isDirectory: &isDir)

        if fileExists && !isDir.boolValue {
            let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }

            try fm.unzipItem(at: packageURL, to: tempDir)
            try validate(packageURL: tempDir)
            return
        }

        guard ProjectPackageManager.shared.validatePackageStructure(at: packageURL) else {
            throw ProjectErrorManager.ProjectError.corruptedPackage("Invalid directory structure")
        }

        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        guard ProjectFileManager.shared.exists(at: manifestURL) else {
            throw ProjectErrorManager.ProjectError.manifestMissing
        }

        let manifestData = try ProjectFileManager.shared.readFile(at: manifestURL)
        let manifest = try ProjectJSONManager.shared.decode(ProjectManifest.self, from: manifestData)
        try ManifestProjManager.shared.validateManifest(manifest)

        guard ProjectVersionManager.shared.checkCompatibility(manifest: manifest) else {
            throw ProjectErrorManager.ProjectError.versionIncompatible(ProjectVersionManager.shared.currentSchemaVersion, manifest.versioning.schemaVersion)
        }

        guard try ProjectIntegrityManager.shared.verifyIntegrity(at: packageURL, manifest: manifest) else {
            throw ProjectErrorManager.ProjectError.securityFailure("Integrity check failed")
        }

        try ProjectResourceManager.shared.validateResources(at: packageURL)
    }
}
