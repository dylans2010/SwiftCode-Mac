import Foundation

public final class ProjectPackageManager {
    public static let shared = ProjectPackageManager()
    private init() {}

    private let fm = FileManager.default

    public func createPackageStructure(at url: URL) throws {
        let directories = [
            "Sources",
            "Assets",
            "Resources",
            "Settings",
            "Frameworks"
        ]

        for dir in directories {
            let dirURL = url.appendingPathComponent(dir)
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }

    public func validatePackageStructure(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        // At minimum, it must be a directory. Specific file checks are in ProjectValidator.
        return true
    }

    public func deletePackage(at url: URL) throws {
        try ProjectFileManager.shared.removeItem(at: url)
    }

    public func duplicatePackage(at src: URL, to dst: URL) throws {
        try ProjectFileManager.shared.copyItem(at: src, to: dst)
    }

    public func cleanupPackage(at url: URL) throws {
        // Remove temporary or redundant files
    }
}
