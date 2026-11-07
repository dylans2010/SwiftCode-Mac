import Foundation
import os.log

actor ProjectOpeningCoordinator {
    static let defaultTimeout: TimeInterval = 15.0

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

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectOpening")
    private var fm: FileManager { .default }

    init() {}

    func loadProjectWithTimeout(url: URL, timeout: TimeInterval = defaultTimeout) async throws -> Project {
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
                throw ProjectOpenError.cancelled
            } else if loadTask.isCancelled {
                self.logger.error("Project load timed out after \(timeout)s")
                throw ProjectOpenError.timeout
            }
            throw error
        }
    }

    private func resolveAndLoad(url: URL) async throws -> Project {
        logger.info("Starting load for project at: \(url.path)")

        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        try Task.checkCancellation()

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            logger.error("Project path not found or not a directory: \(url.path)")
            throw ProjectOpenError.pathNotFound
        }

        let metaURL = url.appendingPathComponent("project.json")
        guard fm.fileExists(atPath: metaURL.path) else {
            logger.error("Metadata missing at: \(metaURL.path)")
            throw ProjectOpenError.corruptedProjectFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data: Data
        do {
            data = try Data(contentsOf: metaURL)
        } catch {
            logger.error("Failed to read metadata: \(error.localizedDescription)")
            throw ProjectOpenError.underlyingIO(error)
        }

        try Task.checkCancellation()

        var project: Project
        do {
            project = try decoder.decode(Project.self, from: data)
        } catch {
            logger.error("Failed to decode metadata: \(error.localizedDescription)")
            throw ProjectOpenError.corruptedProjectFile
        }

        if project.ciBuildConfiguration == nil {
            project.ciBuildConfiguration = CIBuildConfiguration()
        }
        if project.transferConfiguration == nil {
            project.transferConfiguration = .owner
        }

        try Task.checkCancellation()

        project.files = try await buildFileTreeInternal(at: url, relativeTo: url)

        logger.info("Successfully loaded project: \(project.name)")
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
