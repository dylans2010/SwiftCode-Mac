import Foundation

public final class ProjectIntegrityManager {
    public static let shared = ProjectIntegrityManager()
    private init() {}

    public func verifyIntegrity(at packageURL: URL, manifest: ProjectManifest) throws -> Bool {
        // Verification logic using hashes from manifest
        guard let expectedHash = manifest.security.packageIntegrityHash else {
            return true // No hash to verify
        }

        // Simplified check: verify manifest hash if present
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let actualHash = ProjectHashManager.shared.hash(data: manifestData)

        if let expectedManifestHash = manifest.security.manifestHash, actualHash != expectedManifestHash {
            return false
        }

        return true
    }

    public func detectCorruption(at packageURL: URL) -> Bool {
        // Basic check: manifest.json exists
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifestURL.path)
    }
}
