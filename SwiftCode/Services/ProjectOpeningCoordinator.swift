import Foundation
import os.log

actor ProjectOpeningCoordinator {
    static let defaultTimeout: TimeInterval = 15.0

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectOpening")
    private let fm = FileManager.default

    init() {}

    func loadProjectWithTimeout(url: URL, timeout: TimeInterval = defaultTimeout) async throws -> Project {
        try await withThrowingTaskGroup(of: Project.self) { group in
            group.addTask {
                try await self.resolveAndLoad(url: url)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.logger.error("Project load timed out after \(timeout)s")
                throw ProjectOpenError.timeout
            }

            guard let result = try await group.next() else {
                throw ProjectOpenError.cancelled
            }

            group.cancelAll()
            return result
        }
    }

    private func resolveAndLoad(url: URL) async throws -> Project {
        logger.info("Starting load for project at: \(url.path)")

        // 1. Resolve security-scoped bookmark if necessary
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        try Task.checkCancellation()

        // 2. Validate path
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            logger.error("Project path not found or not a directory: \(url.path)")
            throw ProjectOpenError.pathNotFound
        }

        // 3. Parse project.json
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

        // 4. Ensure necessary configurations exist
        if project.ciBuildConfiguration == nil {
            project.ciBuildConfiguration = CIBuildConfiguration()
        }
        if project.transferConfiguration == nil {
            project.transferConfiguration = .owner
        }

        try Task.checkCancellation()

        // 5. Build file tree
        let files = try await buildFileTreeInternal(at: url, relativeTo: url)
        project.files = files

        logger.info("Successfully loaded project: \(project.name)")
        return project
    }

    func buildFileTreeInternal(at url: URL, relativeTo base: URL) async throws -> [FileNode] {
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )

        let basePath = base.standardizedFileURL.path

        let metadataFiles = [
            "manifest.json", "metadata.json", "integrity.json",
            "version.json", "project.json", "project.xml", "project.plist"
        ]

        var nodes: [FileNode] = []

        for childURL in contents {
            try Task.checkCancellation()

            if metadataFiles.contains(childURL.lastPathComponent) { continue }

            let resourceValues = try childURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues.isDirectory ?? false
            let childPath = childURL.standardizedFileURL.path

            let relativePath = childPath.hasPrefix(basePath + "/")
                ? String(childPath.dropFirst(basePath.count + 1))
                : childURL.lastPathComponent

            nodes.append(FileNode(name: childURL.lastPathComponent, path: relativePath, isDirectory: isDir))
        }

        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
