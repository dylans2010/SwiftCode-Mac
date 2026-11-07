import Foundation
import ZIPFoundation

final class ZipImporter: Sendable {
    static let shared = ZipImporter()
    private init() {}

    func exportZip(for project: Project) async throws -> URL {
        let fm = FileManager.default
        let projectDir = await MainActor.run { project.directoryURL }
        let zipName = "\(project.name).zip"
        let destURL = fm.temporaryDirectory.appendingPathComponent(zipName)
        try? fm.removeItem(at: destURL)
        try fm.zipItem(at: projectDir, to: destURL)
        return destURL
    }

    func importZip(at zipURL: URL) async throws -> Project {
        let fm = FileManager.default
        let projectName = zipURL.deletingPathExtension().lastPathComponent
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try unzip(zipURL, to: tempDir)

        let extractedRoot = try findExtractedRoot(in: tempDir)
        let sanitized = sanitizeName(projectName)

        let baseDir = await MainActor.run { ProjectSessionStore.shared.projectsDirectory }
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

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = try encoder.encode(project)
        try metadata.write(to: destDir.appendingPathComponent("project.json"))

        let finalProject = project
        await MainActor.run {
            ProjectSessionStore.shared.projects.insert(finalProject, at: 0)
        }

        return project
    }

    private func unzip(_ zipURL: URL, to destination: URL) throws {
        try FileManager.default.unzipItem(at: zipURL, to: destination)
    }

    private func findExtractedRoot(in directory: URL) throws -> URL {
        let fm = FileManager.default
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

    private func copyContents(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        for item in contents {
            let itemName = item.lastPathComponent

            guard !itemName.contains(".."), !itemName.hasPrefix("/") else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            let destItem = destination.appendingPathComponent(itemName)

            guard destItem.path.hasPrefix(destination.path) else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            try fm.copyItem(at: item, to: destItem)
        }
    }

    private func buildFileTree(at url: URL, relativeTo base: URL) -> [FileNode] {
        let fm = FileManager.default
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
