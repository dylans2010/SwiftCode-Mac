import Foundation

// Implements standard file-system operations using FileManager.
// Thread-safe for concurrent access: mutable working-directory state is guarded by a lock.
public final class AssistFileSystem: @unchecked Sendable, AssistFileSystemProtocol {
    private let fileManager = FileManager.default
    private let workspaceRoot: URL
    private let lock = NSLock()
    private var _currentDirectory: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
        self._currentDirectory = workspaceRoot
    }

    /// Session working directory for relative-path resolution (see `dir_cd`).
    /// Defaults to the workspace root. Plain relative paths resolve against it;
    /// paths with a leading "/" resolve against the workspace root.
    public var currentDirectory: URL {
        lock.withLock { _currentDirectory }
    }

    /// Restore a previously stored working directory (used by the context builder
    /// to re-apply a session's `dir_cd` across messages). Throws if the stored
    /// directory is missing, not a directory, or outside the workspace root.
    public func restoreCurrentDirectory(_ url: URL) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw NSError(domain: "PathSecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security Error: Stored working directory is outside workspace bounds: \(url.path)"])
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "PathSecurityError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stored working directory does not exist or is not a directory: \(url.path)"])
        }
        lock.withLock { _currentDirectory = resolved }
    }

    /// Change the session working directory. `path` is resolved against the
    /// current directory (so `..` moves to the parent, clamped at the workspace
    /// root by the containment check). Returns the new directory.
    public func setCurrentDirectory(_ path: String) throws -> URL {
        let target = try resolve(path)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "PathSecurityError", code: 404, userInfo: [NSLocalizedDescriptionKey: "Directory does not exist or is not a directory: \(path)"])
        }
        lock.withLock { _currentDirectory = target }
        return target
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

    public func deleteDirectory(at path: String) throws {
        let url = try resolve(path)
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path != root.path else {
            throw NSError(domain: "PathSecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "Security Error: Refusing to delete the workspace root itself: \(path)"])
        }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw NSError(domain: "PathSecurityError", code: 404, userInfo: [NSLocalizedDescriptionKey: "No directory at \(path) — nothing to delete."])
        }
        try fileManager.removeItem(at: url)
    }

    public func moveFile(from: String, to: String) throws {
        let fromURL = try resolve(from)
        let toURL = try resolve(to)
        // Never delete the destination before the move succeeds: a failed move
        // must not destroy the previous destination content.
        guard !fileManager.fileExists(atPath: toURL.path) else {
            throw NSError(domain: "PathSecurityError", code: 409, userInfo: [NSLocalizedDescriptionKey: "Destination already exists: \(to). Delete it first or choose another destination."])
        }
        try fileManager.moveItem(at: fromURL, to: toURL)
    }

    public func copyFile(from: String, to: String) throws {
        let fromURL = try resolve(from)
        let toURL = try resolve(to)
        // Never delete the destination before the copy succeeds.
        guard !fileManager.fileExists(atPath: toURL.path) else {
            throw NSError(domain: "PathSecurityError", code: 409, userInfo: [NSLocalizedDescriptionKey: "Destination already exists: \(to). Delete it first or choose another destination."])
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
        // Fail closed when no project is open: the builder falls back to "/"
        // for a missing project, and a "/" workspace root would otherwise
        // make the containment check below pass for every path on disk.
        guard workspaceRoot.path != "/" else {
            throw NSError(domain: "PathSecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "No active project: workspace root is unavailable. Open a project first."])
        }
        // Absolute workspace paths (workspaceRoot prefix) and leading-"/" paths
        // resolve against the workspace root, preserving historical behavior.
        // Plain relative paths resolve against the session working directory
        // (see dir_cd); the containment check below still clamps to the root.
        let base: URL
        let normalizedPath: String
        if path.hasPrefix(workspaceRoot.path) {
            base = workspaceRoot
            normalizedPath = String(path.dropFirst(workspaceRoot.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if path.hasPrefix("/") {
            base = workspaceRoot
            normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            base = currentDirectory
            normalizedPath = path
        }
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        // Resolve symlinks in the longest existing ancestor so a symlink in an
        // existing parent is caught even when the leaf does not exist yet.
        var probe = base.appendingPathComponent(normalizedPath).standardized
        var suffix: [String] = []
        while !fileManager.fileExists(atPath: probe.path) && probe.path != root.path && probe.path != base.standardized.path {
            suffix.insert(probe.lastPathComponent, at: 0)
            probe = probe.deletingLastPathComponent()
        }
        var resolvedURL = probe.resolvingSymlinksInPath()
        for component in suffix { resolvedURL.appendPathComponent(component) }
        resolvedURL = resolvedURL.standardized
        guard resolvedURL.path == root.path || resolvedURL.path.hasPrefix(root.path + "/") else {
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
