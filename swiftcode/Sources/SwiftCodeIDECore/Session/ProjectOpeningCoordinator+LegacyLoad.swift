import Foundation
import os.log

fileprivate typealias LegacyProjectOpenError = ProjectOpenError

private let legacyProjectOpeningLogger = Logger(subsystem: "com.swiftcode.app", category: "ProjectOpening")

extension ProjectOpeningCoordinator {
    private var fm: FileManager { .default }

    private enum FileTreeDefaults {
        static let directoryReadKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        static let metadataFilenames: Set<String> = [
            "manifest.json", "metadata.json", "integrity.json",
            "version.json", "project.json", "project.xml", "project.plist"
        ]
        static let deferredDirectoryNames: Set<String> = [
            ".build", ".git", "DerivedData", "node_modules", "Pods", "build"
        ]
    }

    func loadProjectWithTimeout(url: URL, timeout: TimeInterval = 15.0) async throws -> Project {
        let loadTask = Task {
            try await self.resolveAndLoad(url: url)
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            loadTask.cancel()
        }

        do {
            let project = try await loadTask.value
            timeoutTask.cancel()
            return project
        } catch {
            timeoutTask.cancel()
            if Task.isCancelled {
                throw LegacyProjectOpenError.cancelled
            } else if loadTask.isCancelled {
                legacyProjectOpeningLogger.error("Project load timed out after \(timeout)s")
                throw LegacyProjectOpenError.timeout
            }
            throw error
        }
    }

    private func resolveAndLoad(url: URL) async throws -> Project {
        legacyProjectOpeningLogger.info("Starting load for project at: \(url.path)")

        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        try Task.checkCancellation()

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            legacyProjectOpeningLogger.error("Project path not found or not a directory: \(url.path)")
            throw LegacyProjectOpenError.pathNotFound
        }

        let metaURL = url.appendingPathComponent("project.json")
        guard fm.fileExists(atPath: metaURL.path) else {
            legacyProjectOpeningLogger.error("Metadata missing at: \(metaURL.path)")
            throw LegacyProjectOpenError.corruptedProjectFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data: Data
        do {
            data = try Data(contentsOf: metaURL)
        } catch {
            legacyProjectOpeningLogger.error("Failed to read metadata: \(error.localizedDescription)")
            throw LegacyProjectOpenError.underlyingIO(error)
        }

        try Task.checkCancellation()

        var project: Project
        do {
            project = try decoder.decode(Project.self, from: data)
        } catch {
            legacyProjectOpeningLogger.error("Failed to decode metadata: \(error.localizedDescription)")
            throw LegacyProjectOpenError.corruptedProjectFile
        }

        if project.ciBuildConfiguration == nil {
            project.ciBuildConfiguration = CIBuildConfiguration()
        }
#if canImport(SwiftCodeCollaboration)
        if project.transferConfiguration == nil {
            project.transferConfiguration = .owner
        }
#endif

        try Task.checkCancellation()

        project.files = try await buildFileTreeInternal(at: url, relativeTo: url)

        legacyProjectOpeningLogger.info("Successfully loaded project: \(project.name)")
        return project
    }

    private nonisolated func buildFileTree(at url: URL, relativeTo base: URL) throws -> [FileNode] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(FileTreeDefaults.directoryReadKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        let basePath = base.standardizedFileURL.path
        var nodes: [FileNode] = []

        for childURL in contents {
            try Task.checkCancellation()

            let filename = childURL.lastPathComponent
            if FileTreeDefaults.metadataFilenames.contains(filename) { continue }

            let resourceValues = try childURL.resourceValues(forKeys: FileTreeDefaults.directoryReadKeys)
            let isDirectory = resourceValues.isDirectory ?? false
            if resourceValues.isSymbolicLink == true || (isDirectory && FileTreeDefaults.deferredDirectoryNames.contains(filename)) {
                continue
            }

            let childPath = childURL.standardizedFileURL.path
            let relativePath = childPath.hasPrefix(basePath + "/")
                ? String(childPath.dropFirst(basePath.count + 1))
                : filename

            nodes.append(FileNode(name: filename, path: relativePath, isDirectory: isDirectory))
        }

        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func buildFileTreeInternal(at url: URL, relativeTo base: URL) async throws -> [FileNode] {
        try await Task.detached(priority: .userInitiated) {
            try self.buildFileTree(at: url, relativeTo: base)
        }.value
    }
}
