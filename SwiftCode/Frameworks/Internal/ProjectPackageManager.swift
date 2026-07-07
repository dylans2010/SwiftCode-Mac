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
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.lastPathComponent == ".DS_Store" {
                    try? fm.removeItem(at: fileURL)
                }
            }
        }

        // Remove empty directories in Sources, Assets, Resources
        let subs = ["Sources", "Assets", "Resources", "Frameworks"]
        for sub in subs {
            let subURL = url.appendingPathComponent(sub)
            removeEmptyDirectories(at: subURL)
        }
    }

    private func removeEmptyDirectories(at url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }

        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }

        for item in contents {
            removeEmptyDirectories(at: item)
        }

        // Re-check if empty after cleaning children
        if let remaining = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil), remaining.isEmpty {
            // Don't delete the root structural directories themselves, only their empty subdirectories
            if !["Sources", "Assets", "Resources", "Frameworks", "Settings"].contains(url.lastPathComponent) {
                try? fm.removeItem(at: url)
            }
        }
    }
}
