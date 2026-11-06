import Foundation

public final class ProjectIntegrityManager: Sendable {
    public static let shared = ProjectIntegrityManager()
    private init() {}

    public func verifyIntegrity(at packageURL: URL, manifest: ProjectManifest) throws -> Bool {
        // 1. Verify Manifest Hash if present
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        if let expectedManifestHash = manifest.security.manifestHash {
            let manifestData = try Data(contentsOf: manifestURL)
            let actualManifestHash = ProjectHashManager.shared.hash(data: manifestData)
            if actualManifestHash != expectedManifestHash {
                return false
            }
        }

        // 2. Verify Package Integrity Hash (all files except manifest and integrity)
        guard let expectedPackageHash = manifest.security.packageIntegrityHash else {
            return true // Nothing more to verify
        }

        let actualPackageHash = try calculatePackageHash(at: packageURL)
        return actualPackageHash == expectedPackageHash
    }

    private func calculatePackageHash(at packageURL: URL) throws -> String {
        let fm = FileManager.default
        var combinedHash = ""

        if let enumerator = fm.enumerator(at: packageURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var fileURLs: [URL] = []
            for case let fileURL as URL in enumerator {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isFile {
                    let filename = fileURL.lastPathComponent
                    if filename != "manifest.json" && filename != "integrity.json" {
                        fileURLs.append(fileURL)
                    }
                }
            }

            // Sort URLs for deterministic hashing
            fileURLs.sort { $0.path < $1.path }

            for url in fileURLs {
                combinedHash += try ProjectHashManager.shared.hashFile(at: url)
            }
        }

        return combinedHash.isEmpty ? "" : ProjectHashManager.shared.hash(data: combinedHash.data(using: .utf8)!)
    }

    public func detectCorruption(at packageURL: URL) -> Bool {
        // Basic check: manifest.json exists
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifestURL.path)
    }
}
