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
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("[BEGIN] loadProjectWithTimeout - Parent: None, Child: resolveAndLoad | Thread: \(Thread.isMainThread ? "Main" : "Background") | Actor: ProjectOpeningCoordinator")

        return try await withThrowingTaskGroup(of: Project.self) { group in
            group.addTask {
                try await self.resolveAndLoad(url: url)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.logger.warning("[TIMEOUT] loadProjectWithTimeout - elapsed: \(timeout)s | Actor: ProjectOpeningCoordinator")
                throw ProjectOpenError.timeout
            }

            do {
                guard let result = try await group.next() else {
                    self.logger.error("[FAILED] loadProjectWithTimeout - group next returned nil | Actor: ProjectOpeningCoordinator")
                    throw ProjectOpenError.cancelled
                }
                group.cancelAll()
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                self.logger.info("[END] loadProjectWithTimeout - Success | Elapsed: \(elapsed, format: .fixed(precision: 4))s | Actor: ProjectOpeningCoordinator")
                return result
            } catch is CancellationError {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                self.logger.warning("[CANCELLED] loadProjectWithTimeout | Elapsed: \(elapsed, format: .fixed(precision: 4))s | Actor: ProjectOpeningCoordinator")
                throw ProjectOpenError.cancelled
            } catch {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                self.logger.error("[FAILED] loadProjectWithTimeout - Error: \(error.localizedDescription) | Elapsed: \(elapsed, format: .fixed(precision: 4))s | Actor: ProjectOpeningCoordinator")
                throw error
            }
        }
    }

    private func resolveAndLoad(url: URL) async throws -> Project {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.info("[BEGIN] resolveAndLoad - Parent: loadProjectWithTimeout, Child: buildFileTreeInternal | Thread: \(Thread.isMainThread ? "Main" : "Background") | Actor: ProjectOpeningCoordinator")
        logger.info("Starting load for project at: \(url.path)")

        // 1. Resolve security-scoped bookmark if necessary
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        try Task.checkCancellation()

        // 2. Validate path
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            logger.error("[FAILED] resolveAndLoad - Project path not found: \(url.path) | Actor: ProjectOpeningCoordinator")
            throw ProjectOpenError.pathNotFound
        }

        // 3. Parse project.json
        let metaURL = url.appendingPathComponent("project.json")
        guard fm.fileExists(atPath: metaURL.path) else {
            logger.error("[FAILED] resolveAndLoad - Metadata missing at: \(metaURL.path) | Actor: ProjectOpeningCoordinator")
            throw ProjectOpenError.corruptedProjectFile
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data: Data
        do {
            data = try Data(contentsOf: metaURL)
        } catch {
            logger.error("[FAILED] resolveAndLoad - Failed to read metadata: \(error.localizedDescription) | Actor: ProjectOpeningCoordinator")
            throw ProjectOpenError.underlyingIO(error)
        }

        try Task.checkCancellation()

        var project: Project
        do {
            project = try decoder.decode(Project.self, from: data)
            logger.info("Project Metadata Loaded for: \(project.name)")
        } catch {
            logger.error("[FAILED] resolveAndLoad - Failed to decode metadata: \(error.localizedDescription) | Actor: ProjectOpeningCoordinator")
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

        // 5. Build only the initial navigator level. The workspace lazily expands folders later,
        // which avoids recursive package traversal and oversized project metadata during open.
        project.files = try await buildFileTreeInternal(at: url, relativeTo: url)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("[END] resolveAndLoad - Success | Elapsed: \(elapsed, format: .fixed(precision: 4))s | Actor: ProjectOpeningCoordinator")
        if elapsed > 1.0 {
            logger.warning("[PERFORMANCE WARNING] resolveAndLoad took \(elapsed, format: .fixed(precision: 4))s which is over acceptable threshold of 1s.")
        }
        logger.info("Successfully loaded project: \(project.name)")
        return project
    }

    nonisolated private func buildFileTree(at url: URL, relativeTo base: URL) throws -> [FileNode] {
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

    // Retained for backward compatibility/external interface callers
    func buildFileTreeInternal(at url: URL, relativeTo base: URL) async throws -> [FileNode] {
        try await Task.detached(priority: .userInitiated) {
            try self.buildFileTree(at: url, relativeTo: base)
        }.value
    }
}
