import Foundation

// MARK: - Workspace bridge
//
// The bridge is the only path by which extension-host code touches the
// file system, and it is capability-gated on every call. Workspace
// containment is enforced by path prefix after resolving symlinks:
// a workspace-relative path that resolves outside the root is rejected
// even if it looks relative. Git access goes through the real `git`
// binary in the workspace root (read-only commands only).

public struct ExtV2WorkspaceFile: Sendable {
    public let relativePath: String
    public let isDirectory: Bool
}

public final class ExtV2WorkspaceBridge: Sendable {
    public let root: URL
    private let permissions: ExtV2PermissionManager

    public init(root: URL, permissions: ExtV2PermissionManager) {
        self.root = root
        self.permissions = permissions
    }

    public func resolvedPath(for relativePath: String, extensionId: String) throws -> URL {
        guard !relativePath.hasPrefix("/") else {
            throw ExtV2Error.invalidRequest("Workspace paths must be relative: \(relativePath)")
        }
        let candidate = root.appendingPathComponent(relativePath)
        let resolvedRoot = root.resolvingSymlinksInPath().standardized
        let resolved = candidate.resolvingSymlinksInPath().standardized
        guard resolved == resolvedRoot || resolved.path.hasPrefix(resolvedRoot.path + "/") else {
            throw ExtV2Error.invalidRequest("Path escapes the workspace: \(relativePath)")
        }
        return resolved
    }

    public func listFiles(extensionId: String) throws -> [ExtV2WorkspaceFile] {
        try permissions.check(extensionId: extensionId, capability: .workspaceRead)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var files: [ExtV2WorkspaceFile] = []
        for case let url as URL in enumerator {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            files.append(ExtV2WorkspaceFile(relativePath: relative, isDirectory: isDirectory ?? false))
            if files.count > 20_000 { break }
        }
        return files
    }

    public func readFile(relativePath: String, extensionId: String) throws -> String {
        try permissions.check(extensionId: extensionId, capability: .workspaceRead)
        let url = try resolvedPath(for: relativePath, extensionId: extensionId)
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw ExtV2Error.unknown("Could not read '\(relativePath)': \(error.localizedDescription)")
        }
    }

    public func writeFile(relativePath: String, content: String, extensionId: String) throws {
        try permissions.check(extensionId: extensionId, capability: .workspaceWrite)
        let url = try resolvedPath(for: relativePath, extensionId: extensionId)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(
            name: .ExtV2WorkspaceFileDidChange,
            object: nil,
            userInfo: ["path": relativePath, "extensionId": extensionId])
        ExtV2DiagnosticsService.shared.info("Wrote \(relativePath)", extensionId: extensionId)
    }

    /// Read-only git status for the workspace, via the real git binary.
    public func gitStatus(extensionId: String) throws -> String {
        try permissions.check(extensionId: extensionId, capability: .sourceControl)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "status", "--short"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw ExtV2Error.unknown("git status failed in this workspace.")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

public extension Notification.Name {
    static let ExtV2WorkspaceFileDidChange = Notification.Name("ExtV2WorkspaceFileDidChange")
    static let ExtV2DocumentDidChange = Notification.Name("ExtV2DocumentDidChange")
}
