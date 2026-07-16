import Foundation

public final class AssistFileSystem: AssistFileSystemProtocol {
    private let fileManager = FileManager.default
    private let workspaceRoot: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    public func readFile(at path: String) throws -> String {
        let url = resolve(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func writeFile(at path: String, content: String) throws {
        let url = resolve(path)
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func deleteFile(at path: String) throws {
        let url = resolve(path)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func moveFile(from: String, to: String) throws {
        let fromURL = resolve(from)
        let toURL = resolve(to)
        if fileManager.fileExists(atPath: toURL.path) {
            try fileManager.removeItem(at: toURL)
        }
        try fileManager.moveItem(at: fromURL, to: toURL)
    }

    public func copyFile(from: String, to: String) throws {
        let fromURL = resolve(from)
        let toURL = resolve(to)
        if fileManager.fileExists(atPath: toURL.path) {
            try fileManager.removeItem(at: toURL)
        }
        try fileManager.copyItem(at: fromURL, to: toURL)
    }

    public func exists(at path: String) -> Bool {
        let url = resolve(path)
        return fileManager.fileExists(atPath: url.path)
    }

    public func appendFile(at path: String, content: String) throws {
        let url = resolve(path)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try writeFile(at: path, content: existing + content)
    }

    public func createDirectory(at path: String) throws {
        let url = resolve(path)
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }


    private func resolve(_ path: String) -> URL {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let resolvedURL = workspaceRoot.appendingPathComponent(normalizedPath).standardized

        // Safety: Ensure the resolved path is within the workspace root
        if !resolvedURL.path.hasPrefix(workspaceRoot.path) {
            // Log security violation if we had access to logger here,
            // for now, fallback to a safe path within workspace
            return workspaceRoot.appendingPathComponent("safe_fallback_\(UUID().uuidString)")
        }

        return resolvedURL
    }

    // Additional internal helpers
    public func listDirectory(at path: String) throws -> [String] {
        let url = resolve(path)
        return try fileManager.contentsOfDirectory(atPath: url.path)
    }
}
