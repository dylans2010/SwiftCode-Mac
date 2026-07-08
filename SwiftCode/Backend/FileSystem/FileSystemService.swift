import Foundation

public actor FileSystemService {
    public static let shared = FileSystemService()

    public func listDirectory(at url: URL, recursive: Bool = false) throws -> [ProjectNode] {
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])

        return try contents.map { itemURL in
            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            var children: [ProjectNode]? = nil
            if isDirectory && recursive {
                children = try listDirectory(at: itemURL, recursive: true)
            }
            return ProjectNode(url: itemURL, kind: isDirectory ? .folder : .file, children: children)
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
        try finalContent.write(to: url, options: .atomic, encoding: .utf8)
    }

    public func delete(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
