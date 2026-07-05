import Foundation
import ZIPFoundation

/// Handles importing a .zip archive and converting it into a SwiftCode project.
final class ZipImporter {
    static let shared = ZipImporter()
    private init() {}

    private let fm = FileManager.default

    // MARK: - Export

    /// Exports an existing project directory as a .zip file and returns the local URL.
    func exportZip(for project: Project) async throws -> URL {
        let projectDir = await MainActor.run { project.directoryURL }
        let zipName = "\(project.name).zip"
        let destURL = fm.temporaryDirectory.appendingPathComponent(zipName)
        // Remove old export if present
        try? fm.removeItem(at: destURL)
        try fm.zipItem(at: projectDir, to: destURL)
        return destURL
    }

    // MARK: - Import

    /// Import a zip file, creating a new project with the extracted contents.
    /// - Parameter zipURL: The source .zip file URL.
    /// - Returns: The newly created Project.
    func importZip(at zipURL: URL) async throws -> Project {
        let projectName = zipURL.deletingPathExtension().lastPathComponent
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try unzip(zipURL, to: tempDir)

        let extractedRoot = try findExtractedRoot(in: tempDir)
        let sanitized = sanitizeName(projectName)

        // Build destination project directory, handling name collisions.
        let baseDir = await MainActor.run { ProjectManager.shared.projectsDirectory }
        var finalName = sanitized
        var destDir = baseDir.appendingPathComponent(finalName)
        var counter = 2
        while fm.fileExists(atPath: destDir.path) {
            finalName = "\(sanitized) \(counter)"
            destDir = baseDir.appendingPathComponent(finalName)
            counter += 1
        }

        try copyContents(from: extractedRoot, to: destDir)

        var project = Project(name: finalName)
        project.files = buildFileTree(at: destDir, relativeTo: destDir)

        // Save metadata using the same encoder pattern as ProjectManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = try encoder.encode(project)
        try metadata.write(to: destDir.appendingPathComponent("project.json"))

        let finalProject = project
        await MainActor.run {
            ProjectManager.shared.projects.insert(finalProject, at: 0)
        }

        return project
    }

    // MARK: - Unzip (using ZIPFoundation)

    private func unzip(_ zipURL: URL, to destination: URL) throws {
        try fm.unzipItem(at: zipURL, to: destination)
    }

    // MARK: - Find Root

    /// If the zip contains a single top-level directory, return it; otherwise return the temp dir itself.
    private func findExtractedRoot(in directory: URL) throws -> URL {
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        if contents.count == 1,
           let single = contents.first,
           (try? single.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return single
        }
        return directory
    }

    // MARK: - Copy Contents with Path Validation

    private func copyContents(from source: URL, to destination: URL) throws {
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        for item in contents {
            let itemName = item.lastPathComponent

            // Validate: prevent directory traversal attacks.
            guard !itemName.contains(".."), !itemName.hasPrefix("/") else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            let destItem = destination.appendingPathComponent(itemName)

            // Ensure destination stays inside the project directory.
            guard destItem.path.hasPrefix(destination.path) else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            try fm.copyItem(at: item, to: destItem)
        }
    }

    // MARK: - File Tree

    private func buildFileTree(at url: URL, relativeTo base: URL) -> [FileNode] {
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let basePath = base.standardizedFileURL.path

        return contents
            .filter { $0.lastPathComponent != "project.json" }
            .sorted {
                let aIsDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bIsDir = (try? $1.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aIsDir != bIsDir { return aIsDir }
                return $0.lastPathComponent < $1.lastPathComponent
            }
            .map { childURL -> FileNode in
                let isDir = (try? childURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let childPath = childURL.standardizedFileURL.path
                let relativePath = childPath.hasPrefix(basePath + "/")
                    ? String(childPath.dropFirst(basePath.count + 1))
                    : childURL.lastPathComponent
                let node = FileNode(name: childURL.lastPathComponent, path: relativePath, isDirectory: isDir)
                if isDir {
                    node.children = buildFileTree(at: childURL, relativeTo: base)
                }
                return node
            }
    }

    // MARK: - Helpers

    private let maxProjectNameLength = 64

    private func sanitizeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return name
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxProjectNameLength)
            .description
    }
}

// MARK: - Errors

enum ZipImporterError: LocalizedError {
    case extractionFailed
    case projectAlreadyExists(name: String)
    case unsafePath(path: String)

    var errorDescription: String? {
        switch self {
        case .extractionFailed:
            return "Failed to extract the zip archive."
        case .projectAlreadyExists(let name):
            return "A project named '\(name)' already exists."
        case .unsafePath(let path):
            return "The archive contains an unsafe file path: \(path)"
        }
    }
}
