import Foundation

public final class ProjectFileManager: Sendable {
    public static let shared = ProjectFileManager()
    private init() {}

    public func readFile(at url: URL) throws -> Data {
        return try Data(contentsOf: url)
    }

    public func writeFile(data: Data, to url: URL) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: url, atomically: true)
    }

    public func copyItem(at src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
    }

    public func moveItem(at src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.moveItem(at: src, to: dst)
    }

    public func removeItem(at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    public func exists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
}
