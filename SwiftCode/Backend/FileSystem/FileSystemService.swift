import Foundation

public actor FileSystemService {
    public static let shared = FileSystemService()

    public func listDirectory(at url: URL) throws -> [ProjectNode] {
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

        return contents.map { itemURL in
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return ProjectNode(url: itemURL, kind: isDirectory ? .folder : .file)
        }
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func createFile(at url: URL, content: String = "") throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
