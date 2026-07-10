import Foundation

public actor FileSystemService {
    public static let shared = FileSystemService()

    private enum DirectoryListingDefaults {
        static let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        static let deferredDirectoryNames: Set<String> = [
            ".build", ".git", "DerivedData", "node_modules", "Pods", "build"
        ]
    }

    public func listDirectory(at url: URL, recursive: Bool = false) throws -> [ProjectNode] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(DirectoryListingDefaults.resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        return contents.compactMap { itemURL in
            let values = try? itemURL.resourceValues(forKeys: DirectoryListingDefaults.resourceKeys)
            let isDirectory = values?.isDirectory ?? false
            if values?.isSymbolicLink == true || (isDirectory && DirectoryListingDefaults.deferredDirectoryNames.contains(itemURL.lastPathComponent)) {
                return nil
            }
            return ProjectNode(url: itemURL, kind: isDirectory ? .folder : .file, children: nil)
        }.sorted {
            switch ($0.kind, $1.kind) {
            case (.folder, .file):
                return true
            case (.file, .folder):
                return false
            default:
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        }
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func createFile(at url: URL, content: String = "") async throws {
        var finalContent = content
        if url.pathExtension == "swift" {
            let filename = url.lastPathComponent
            let projectName = "SwiftCode"
            let header = await NewFileComment.generateHeader(filename: filename, projectName: projectName)
            finalContent = header + content
        }
        try finalContent.write(to: url, atomically: true, encoding: .utf8)
    }

    public func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
