import Foundation

// Implements standard file-system operations using FileManager. Immutable and safe for concurrent access.
public final class AssistFileSystem: @unchecked Sendable, AssistFileSystemProtocol {
    private let fileManager = FileManager.default
    private let workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    public func readFile(at path: String) throws -> String {
        let url = try resolve(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeFile(at path: String, content: String) throws {
        let url = try resolve(path)
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func deleteFile(at path: String) throws {
        let url = try resolve(path)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func moveFile(from: String, to: String) throws {
        let fromURL = try resolve(from)
        let toURL = try resolve(to)
        if fileManager.fileExists(atPath: toURL.path) {
            try fileManager.removeItem(at: toURL)
        }
        try fileManager.moveItem(at: fromURL, to: toURL)
    }

    public func copyFile(from: String, to: String) throws {
        let fromURL = try resolve(from)
        let toURL = try resolve(to)
        if fileManager.fileExists(atPath: toURL.path) {
            try fileManager.removeItem(at: toURL)
        }
        try fileManager.copyItem(at: fromURL, to: toURL)
    }

    public func exists(at path: String) -> Bool {
        guard let url = try? resolve(path) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    public func appendFile(at path: String, content: String) throws {
        let url = try resolve(path)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try writeFile(at: path, content: existing + content)
    }

    public func createDirectory(at path: String) throws {
        let url = try resolve(path)
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func resolve(_ path: String) throws -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let resolvedURL = workspaceRoot.appendingPathComponent(normalizedPath).standardized

        // Safety: Ensure the resolved path is within the workspace root
        if !resolvedURL.path.hasPrefix(workspaceRoot.path) {
            throw NSError(domain: "PathSecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security Error: Path traversal outside workspace bounds is forbidden: \(path)"])
        }

        return resolvedURL
    }

    // Additional internal helpers
    public func listDirectory(at path: String) throws -> [String] {
        let url = try resolve(path)
        return try fileManager.contentsOfDirectory(atPath: url.path)
    }
}
