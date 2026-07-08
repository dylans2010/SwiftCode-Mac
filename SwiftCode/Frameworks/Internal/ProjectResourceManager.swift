import Foundation

public final class ProjectResourceManager: Sendable {
    public static let shared = ProjectResourceManager()
    private init() {}

    public func validateResources(at packageURL: URL) throws {
        let fm = FileManager.default
        let requiredDirs = ["Sources", "Resources"]
        for dir in requiredDirs {
            let dirURL = packageURL.appendingPathComponent(dir)
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: dirURL.path, isDirectory: &isDir) || !isDir.boolValue {
                throw ProjectErrorManager.ProjectError.corruptedPackage("Missing required directory: \(dir)")
            }
        }
    }

    public func copyResource(_ resourceURL: URL, to packageURL: URL) throws {
        let destURL = packageURL.appendingPathComponent("Resources").appendingPathComponent(resourceURL.lastPathComponent)
        try ProjectFileManager.shared.copyItem(at: resourceURL, to: destURL)
    }
}
