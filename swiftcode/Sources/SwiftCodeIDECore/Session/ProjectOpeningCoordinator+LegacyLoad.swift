// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/ProjectOpeningCoordinator.swift
//   (Legacy main ab03f681) — the `loadProjectWithTimeout` /
//   `buildFileTreeInternal` half only.
//
// Destination: SwiftCodeIDECore/Session/ProjectOpeningCoordinator+LegacyLoad.swift.
//
// Why an extension file: the landed `ProjectOpeningCoordinator`
// (`Session/ProjectOpeningCoordinator.swift`, batch A2) is a different
// coordinator — it opens `WorkspaceSession`s through `WorkspaceModel`
// with its own nested `ProjectOpenError` (`timeout(URL)`,
// `cancelled`, `failed(URL, Error)`). It cannot serve the session
// store, which loads a `Project` record from `project.json` plus a
// first-level file tree. Rather than re-implementing the load inside
// the store, the two missing Legacy coordinator methods land here, so
// the store's call sites stay verbatim
// (`coordinator.loadProjectWithTimeout(url:)`,
// `coordinator.buildFileTreeInternal(at:relativeTo:)`).
//
// Error-type disambiguation: these methods throw the TOP-LEVEL
// `ProjectOpenError` (`Model/ProjectOpenError.swift`: `.pathNotFound`,
// `.corruptedProjectFile`, `.timeout`, `.cancelled`, `.underlyingIO`),
// not the actor's nested one. Inside an extension of
// `ProjectOpeningCoordinator` the bare name resolves to the nested
// type, so this file aliases the top-level type at file scope
// (`LegacyProjectOpenError`) and uses the alias throughout.
//
// Adaptations (behaviour preserved unless noted):
// * The actor's `timeout` default is 15 seconds, matching Legacy's
//   `defaultTimeout`; the parameter default here is the same literal.
// * Legacy's `logger` / `fm` were private members of its coordinator;
//   the landed actor's `logger` is private to its own file, so this
//   file uses a file-scope logger with the same subsystem/category and
//   a computed `fm` in the extension.
// * `buildFileTree` keeps Legacy's `nonisolated` (it runs in a detached
//   task) and its `Task.checkCancellation()` in the directory loop.

import Foundation
import os.log

/// File-scope alias for the top-level `ProjectOpenError` (see header):
/// inside `ProjectOpeningCoordinator` the bare name means the actor's
/// nested error type, which has different cases.
fileprivate typealias LegacyProjectOpenError = ProjectOpenError

/// Same subsystem/category as Legacy's coordinator logger.
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

        // 1. Resolve security-scoped bookmark if necessary
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        try Task.checkCancellation()

        // 2. Validate path
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            legacyProjectOpeningLogger.error("Project path not found or not a directory: \(url.path)")
            throw LegacyProjectOpenError.pathNotFound
        }

        // 3. Parse project.json
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

        // 4. Ensure necessary configurations exist
        if project.ciBuildConfiguration == nil {
            project.ciBuildConfiguration = CIBuildConfiguration()
        }
#if canImport(SwiftCodeCollaboration)
        if project.transferConfiguration == nil {
            project.transferConfiguration = .owner
        }
#endif

        try Task.checkCancellation()

        // 5. Build only the initial navigator level. The workspace lazily expands folders later,
        // which avoids recursive package traversal and oversized project metadata during open.
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

    // Retained for backward compatibility/external interface callers
    func buildFileTreeInternal(at url: URL, relativeTo base: URL) async throws -> [FileNode] {
        try await Task.detached(priority: .userInitiated) {
            try self.buildFileTree(at: url, relativeTo: base)
        }.value
    }
}
