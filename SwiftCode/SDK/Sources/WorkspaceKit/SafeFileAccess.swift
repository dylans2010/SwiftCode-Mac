import Foundation
import DiagnosticsKit

public enum WorkspaceError: Error, LocalizedError, Sendable {
    case pathNotFound(String)
    case traversalDenied(path: String, root: String)
    case permissionDenied(String)
    case writeFailed(String, String)
    case readFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .pathNotFound(let p):
            return "Workspace path not found: \(p)"
        case .traversalDenied(let path, let root):
            return "Path traversal forbidden: '\(path)' escapes root '\(root)'"
        case .permissionDenied(let p):
            return "Permission denied for workspace path: \(p)"
        case .writeFailed(let p, let reason):
            return "Failed writing file at \(p): \(reason)"
        case .readFailed(let p, let reason):
            return "Failed reading file at \(p): \(reason)"
        }
    }
}

public final class SafeFileAccess: Sendable {
    public let root: WorkspacePath

    public init(root: WorkspacePath) {
        self.root = root
    }

    public func validatePath(_ path: WorkspacePath) throws -> WorkspacePath {
        let normalized = WorkspacePath(path.normalizedPath)
        guard normalized.isWithin(root: root) else {
            throw WorkspaceError.traversalDenied(path: path.rawPath, root: root.normalizedPath)
        }
        return normalized
    }

    public func readFile(at relativeOrAbsolutePath: String) throws -> Data {
        let fullPath = resolve(relativeOrAbsolutePath)
        let safePath = try validatePath(fullPath)
        guard FileManager.default.fileExists(atPath: safePath.normalizedPath) else {
            throw WorkspaceError.pathNotFound(safePath.normalizedPath)
        }
        do {
            return try Data(contentsOf: safePath.url)
        } catch {
            throw WorkspaceError.readFailed(safePath.normalizedPath, error.localizedDescription)
        }
    }

    public func readString(at relativeOrAbsolutePath: String, encoding: String.Encoding = .utf8) throws -> String {
        let data = try readFile(at: relativeOrAbsolutePath)
        guard let string = String(data: data, encoding: encoding) else {
            throw WorkspaceError.readFailed(relativeOrAbsolutePath, "Could not decode data as UTF-8")
        }
        return string
    }

    public func writeFile(data: Data, to relativeOrAbsolutePath: String) throws {
        let fullPath = resolve(relativeOrAbsolutePath)
        let safePath = try validatePath(fullPath)
        let dir = safePath.directoryPath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        do {
            try data.write(to: safePath.url)
        } catch {
            throw WorkspaceError.writeFailed(safePath.normalizedPath, error.localizedDescription)
        }
    }

    public func writeString(_ string: String, to relativeOrAbsolutePath: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw WorkspaceError.writeFailed(relativeOrAbsolutePath, "Could not encode string as UTF-8")
        }
        try writeFile(data: data, to: relativeOrAbsolutePath)
    }

    public func exists(at relativeOrAbsolutePath: String) -> Bool {
        let fullPath = resolve(relativeOrAbsolutePath)
        guard (try? validatePath(fullPath)) != nil else { return false }
        return FileManager.default.fileExists(atPath: fullPath.normalizedPath)
    }

    public func listFiles(recursively: Bool = true) throws -> [WorkspaceFile] {
        var results: [WorkspaceFile] = []
        let fileManager = FileManager.default
        let rootURL = root.url

        if recursively {
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isExecutableKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            for case let fileURL as URL in enumerator {
                let path = fileURL.path
                let safePath = WorkspacePath(path)
                guard safePath.isWithin(root: root) else { continue }
                let rel = String(path.dropFirst(root.normalizedPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let attrs = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isExecutableKey])
                let isDir = attrs?.isDirectory ?? false
                let size = Int64(attrs?.fileSize ?? 0)
                let modDate = attrs?.contentModificationDate ?? Date()
                let isExec = attrs?.isExecutable ?? false
                results.append(WorkspaceFile(
                    path: path,
                    relativePath: rel,
                    isDirectory: isDir,
                    sizeInBytes: size,
                    modificationDate: modDate,
                    isExecutable: isExec
                ))
            }
        } else {
            let contents = try fileManager.contentsOfDirectory(atPath: root.normalizedPath)
            for item in contents {
                let full = root.appending(item)
                let attrs = try? fileManager.attributesOfItem(atPath: full.normalizedPath)
                let isDir = (attrs?[.type] as? FileAttributeType) == .typeDirectory
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                let modDate = (attrs?[.modificationDate] as? Date) ?? Date()
                let posix = (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? 0
                let isExec = (posix & 0o111) != 0
                results.append(WorkspaceFile(
                    path: full.normalizedPath,
                    relativePath: item,
                    isDirectory: isDir,
                    sizeInBytes: size,
                    modificationDate: modDate,
                    isExecutable: isExec
                ))
            }
        }
        return results
    }

    public func resolve(_ pathString: String) -> WorkspacePath {
        if pathString.hasPrefix("/") {
            return WorkspacePath(pathString)
        } else {
            return root.appending(pathString)
        }
    }
}

public struct Workspace: Sendable {
    public let root: WorkspacePath
    public let fileAccess: SafeFileAccess

    public init(root: WorkspacePath) {
        self.root = root
        self.fileAccess = SafeFileAccess(root: root)
    }

    public init(path: String) {
        self.init(root: WorkspacePath(path))
    }

    public func discoverProjects() throws -> [String] {
        let files = try fileAccess.listFiles(recursively: true)
        var projects: [String] = []
        for file in files {
            if file.fileName == "Package.swift" || file.fileName == "swiftcode.json" || file.path.hasSuffix(".xcodeproj") {
                projects.append(file.path)
            }
        }
        return projects
    }
}
