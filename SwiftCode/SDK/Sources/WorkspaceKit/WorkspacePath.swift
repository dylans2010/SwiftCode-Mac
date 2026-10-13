import Foundation
import DiagnosticsKit

public struct WorkspacePath: Sendable, Hashable, CustomStringConvertible {
    public let rawPath: String

    public init(_ rawPath: String) {
        self.rawPath = rawPath
    }

    public var description: String { rawPath }

    public var url: URL {
        URL(fileURLWithPath: rawPath).standardized
    }

    public var normalizedPath: String {
        url.path
    }

    public var fileName: String {
        url.lastPathComponent
    }

    public var fileExtension: String {
        url.pathExtension
    }

    public var directoryPath: String {
        url.deletingLastPathComponent().path
    }

    public func appending(_ component: String) -> WorkspacePath {
        WorkspacePath(url.appendingPathComponent(component).path)
    }

    /// Verifies that this path is within or equal to the designated root path,
    /// protecting against directory traversal attacks (e.g. `../../etc/passwd`).
    public func isWithin(root: WorkspacePath) -> Bool {
        let rootNorm = root.normalizedPath
        let selfNorm = normalizedPath

        if selfNorm == rootNorm { return true }
        let rootPrefix = rootNorm.hasSuffix("/") ? rootNorm : rootNorm + "/"
        return selfNorm.hasPrefix(rootPrefix)
    }
}

public struct WorkspaceFile: Sendable, Codable {
    public let path: String
    public let relativePath: String
    public let isDirectory: Bool
    public let sizeInBytes: Int64
    public let modificationDate: Date
    public let isExecutable: Bool

    public var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public init(
        path: String,
        relativePath: String,
        isDirectory: Bool,
        sizeInBytes: Int64,
        modificationDate: Date,
        isExecutable: Bool
    ) {
        self.path = path
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.sizeInBytes = sizeInBytes
        self.modificationDate = modificationDate
        self.isExecutable = isExecutable
    }
}
