import Foundation

/// Filesystem service (Legacy
/// `SwiftCode/Backend/FileSystem/FileSystemService.swift`, Dylan's own
/// code, ported under MIT).
///
/// The destination had the pieces but not the service: `file_create`
/// never prepended the Swift file header (`NewFileComment.
/// generateHeader` existed and was unused), and no API offered the
/// folders-first sorted listing. This port restores both contracts
/// exactly: deferred directories (`.build`, `.git`, `DerivedData`,
/// `node_modules`, `Pods`, `build`), symlinks excluded, folders
/// first then `localizedStandardCompare` names, and the Swift header
/// on `.swift` creates (author: the current user, project: the
/// workspace's display name when known, else `"SwiftCode"`).
///
/// Wiring: no lifecycle hook — a stateless shared actor. The MCP
/// `file_create` handler should route through this instead of writing
/// directly (see the patched `SwiftCodeTools+FileWriting.swift`).
public actor FileSystemService {
    public static let shared = FileSystemService()

    private enum DirectoryListingDefaults {
        static let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        static let deferredDirectoryNames: Set<String> = [
            ".build", ".git", "DerivedData", "node_modules", "Pods", "build"
        ]
    }

    public init() {}

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
            let isPackage = itemURL.pathExtension == "xcodeproj"
            return ProjectNode(url: itemURL, kind: (isDirectory && !isPackage) ? .folder : .file, children: nil)
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

    public func createFile(at url: URL, content: String = "", projectName: String = "SwiftCode") async throws {
        var finalContent = content
        if url.pathExtension == "swift" {
            let filename = url.lastPathComponent
            let header = NewFileComment.generateHeader(filename: filename, projectName: projectName, userName: NSUserName())
            finalContent = header + content
        }
        try finalContent.write(to: url, atomically: true, encoding: .utf8)
    }

    public func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
