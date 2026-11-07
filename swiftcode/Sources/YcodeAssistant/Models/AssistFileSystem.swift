import Foundation

public final class AssistFileSystem: @unchecked Sendable, AssistFileSystemProtocol {
    private let fileManager = FileManager.default
    private let workspaceRoot: URL
    private let lock = NSLock()
    private var _currentDirectory: URL

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
        self._currentDirectory = workspaceRoot
    }

    public var currentDirectory: URL {
        lock.withLock { _currentDirectory }
    }

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
        guard !fileManager.fileExists(atPath: toURL.path) else {
            throw NSError(domain: "PathSecurityError", code: 409, userInfo: [NSLocalizedDescriptionKey: "Destination already exists: \(to). Delete it first or choose another destination."])
        }
        try fileManager.moveItem(at: fromURL, to: toURL)
    }

    public func copyFile(from: String, to: String) throws {
        let fromURL = try resolve(from)
        let toURL = try resolve(to)
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
        if path == "/tmp/swiftcode/scripts" || path.hasPrefix("/tmp/swiftcode/scripts/") {
            return URL(fileURLWithPath: path).standardized
        }
        guard workspaceRoot.path != "/" else {
            throw NSError(domain: "PathSecurityError", code: 403, userInfo: [NSLocalizedDescriptionKey: "No active project: workspace root is unavailable. Open a project first."])
        }
        let base: URL
        let normalizedPath: String
        if path == workspaceRoot.path || path.hasPrefix(workspaceRoot.path + "/") {
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

    public func listDirectory(at path: String) throws -> [String] {
        let url = try resolve(path)
        return try fileManager.contentsOfDirectory(atPath: url.path)
    }
}
