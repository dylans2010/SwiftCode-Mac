import Foundation

@MainActor
final class CodingManager: ObservableObject {
    static let shared = CodingManager()

    private let fm = FileManager.default

    var projectsRoot: URL

    var modelsRoot: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        projectsRoot = docs.appendingPathComponent("Projects")
        modelsRoot = docs.appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
    }

    /// Ensure the Projects directory exists. Called at app startup.
    func ensureProjectsDirectory() {
        if !fm.fileExists(atPath: projectsRoot.path) {
            try? fm.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        }
    }

    /// Ensure the Models directory exists. Called at app startup.
    func ensureModelsDirectory() {
        if !fm.fileExists(atPath: modelsRoot.path) {
            try? fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        }
    }

    /// List all CoreML model files (.mlmodel, .mlmodelc) in the Models directory.
    func listModels() -> [URL] {
        let extensions: Set<String> = ["mlmodel", "mlmodelc"]
        guard let items = try? fm.contentsOfDirectory(
            at: modelsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return items
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Import a CoreML model file into the Models directory.
    func importModel(from sourceURL: URL) throws -> URL {
        let fileName = sourceURL.lastPathComponent
        guard !fileName.isEmpty, !fileName.contains("/"), !fileName.hasPrefix(".") else {
            throw CodingError.pathOutsideProject
        }
        let destURL = modelsRoot.appendingPathComponent(fileName)
        let resolvedDest = destURL.resolvingSymlinksInPath()
        let resolvedRoot = modelsRoot.resolvingSymlinksInPath()
        guard resolvedDest.path.hasPrefix(resolvedRoot.path + "/") || resolvedDest.path == resolvedRoot.path else {
            throw CodingError.pathOutsideProject
        }
        if fm.fileExists(atPath: resolvedDest.path) {
            try fm.removeItem(at: resolvedDest)
        }
        try fm.copyItem(at: sourceURL, to: resolvedDest)
        return resolvedDest
    }

    /// Delete a CoreML model file from the Models directory.
    func deleteModel(named name: String) throws {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
            throw CodingError.pathOutsideProject
        }
        let url = modelsRoot.appendingPathComponent(name)
        let resolvedURL = url.resolvingSymlinksInPath()
        let resolvedRoot = modelsRoot.resolvingSymlinksInPath()
        guard resolvedURL.path.hasPrefix(resolvedRoot.path + "/") else {
            throw CodingError.pathOutsideProject
        }
        try fm.removeItem(at: resolvedURL)
    }

    // MARK: - Read

    /// Read file content as a string.
    func readFile(at relativePath: String, in projectDir: URL) throws -> String {
        let url = projectDir.appendingPathComponent(relativePath)
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        return try String(contentsOf: standardized, encoding: .utf8)
    }

    /// Read file content asynchronously.
    nonisolated func readFileAsync(at relativePath: String, in projectDir: URL) async throws -> String {
        let url = projectDir.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(projectStd.path + "/") || url.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CodingError.encodingError
        }
        return content
    }

    // MARK: - Write

    /// Write content to a file, creating intermediate directories if needed.
    func writeFile(content: String, at relativePath: String, in projectDir: URL) throws {
        let url = projectDir.appendingPathComponent(relativePath)
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        let parent = standardized.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: standardized, options: .atomic, encoding: .utf8)
    }

    // MARK: - Create

    /// Create a new file with optional initial content.
    func createFile(named name: String, at directoryPath: String?, in projectDir: URL, content: String = "") throws {
        let base = directoryPath.map { projectDir.appendingPathComponent($0) } ?? projectDir
        let fileURL = base.appendingPathComponent(name)
        let standardized = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        guard !fm.fileExists(atPath: standardized.path) else {
            throw CodingError.alreadyExists
        }
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try content.write(to: standardized, options: .atomic, encoding: .utf8)
    }

    /// Create a new directory.
    func createDirectory(named name: String, at directoryPath: String?, in projectDir: URL) throws {
        let base = directoryPath.map { projectDir.appendingPathComponent($0) } ?? projectDir
        let folderURL = base.appendingPathComponent(name)
        let standardized = folderURL.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        try fm.createDirectory(at: standardized, withIntermediateDirectories: false)
    }

    // MARK: - Delete

    /// Delete a file or directory.
    func deleteItem(at relativePath: String, in projectDir: URL) throws {
        let url = projectDir.appendingPathComponent(relativePath)
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        guard standardized.path != projectStd.path else {
            throw CodingError.cannotDeleteRoot
        }
        try fm.removeItem(at: standardized)
    }

    // MARK: - Rename

    /// Rename a file or directory.
    func renameItem(at relativePath: String, to newName: String, in projectDir: URL) throws {
        let oldURL = projectDir.appendingPathComponent(relativePath)
        let parentPath = (relativePath as NSString).deletingLastPathComponent
        let newRelative = parentPath.isEmpty ? newName : "\(parentPath)/\(newName)"
        let newURL = projectDir.appendingPathComponent(newRelative)

        let oldStd = oldURL.standardizedFileURL.resolvingSymlinksInPath()
        let newStd = newURL.standardizedFileURL.resolvingSymlinksInPath()
        let projStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()

        guard oldStd.path.hasPrefix(projStd.path + "/") || oldStd.path == projStd.path,
              newStd.path.hasPrefix(projStd.path + "/") || newStd.path == projStd.path else {
            throw CodingError.pathOutsideProject
        }
        try fm.moveItem(at: oldStd, to: newStd)
    }

    // MARK: - Scan

    /// Scan the project directory and return a list of relative file paths.
    /// Excludes `project.json` which is internal metadata used by ProjectManager.
    func scanProjectFiles(in projectDir: URL) -> [String] {
        var files: [String] = []
        guard let enumerator = fm.enumerator(
            at: projectDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return files }

        let basePath = projectDir.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isFile {
                let relative = url.standardizedFileURL.path.replacingOccurrences(of: basePath + "/", with: "")
                if relative != "project.json" {
                    files.append(relative)
                }
            }
        }
        return files.sorted()
    }

    // MARK: - File Existence

    func fileExists(at relativePath: String, in projectDir: URL) -> Bool {
        let url = projectDir.appendingPathComponent(relativePath)
        return fm.fileExists(atPath: url.standardizedFileURL.path)
    }

    // MARK: - Copy

    /// Copy a file within a project directory.
    func copyFile(from sourcePath: String, to destPath: String, in projectDir: URL) throws {
        let srcURL = projectDir.appendingPathComponent(sourcePath).standardizedFileURL.resolvingSymlinksInPath()
        let dstURL = projectDir.appendingPathComponent(destPath).standardizedFileURL.resolvingSymlinksInPath()
        let projStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard srcURL.path.hasPrefix(projStd.path + "/") || srcURL.path == projStd.path,
              dstURL.path.hasPrefix(projStd.path + "/") || dstURL.path == projStd.path else {
            throw CodingError.pathOutsideProject
        }
        let parent = dstURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try fm.copyItem(at: srcURL, to: dstURL)
    }

    // MARK: - Convenience (project-name based)

    /// Resolve a project directory URL from a project name.
    func projectDirectory(for projectName: String) -> URL {
        projectsRoot.appendingPathComponent(projectName)
    }

    /// Read a file using project name instead of URL.
    func readFile(at relativePath: String, in project: String) throws -> String {
        try readFile(at: relativePath, in: projectDirectory(for: project))
    }

    /// Write a file using project name instead of URL.
    func writeFile(content: String, to relativePath: String, in project: String) throws {
        try writeFile(content: content, at: relativePath, in: projectDirectory(for: project))
    }

    /// Create a file at a relative path inside a named project.
    func createFile(at relativePath: String, in project: String) throws {
        let projectDir = projectDirectory(for: project)
        let url = projectDir.appendingPathComponent(relativePath)
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        let parent = standardized.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: standardized.path) {
            try "".write(to: standardized, options: .atomic, encoding: .utf8)
        }
    }

    /// Delete a file at a relative path inside a named project.
    func deleteFile(at relativePath: String, in project: String) throws {
        try deleteItem(at: relativePath, in: projectDirectory(for: project))
    }

    /// Create a folder at a relative path inside a named project.
    func createFolder(at relativePath: String, in project: String) throws {
        let projectDir = projectDirectory(for: project)
        let url = projectDir.appendingPathComponent(relativePath)
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        try fm.createDirectory(at: standardized, withIntermediateDirectories: true)
    }

    /// Delete a folder at a relative path inside a named project.
    func deleteFolder(at relativePath: String, in project: String) throws {
        try deleteItem(at: relativePath, in: projectDirectory(for: project))
    }

    /// Scan a named project and return its relative file paths.
    func scanProject(projectName: String) -> [String] {
        scanProjectFiles(in: projectDirectory(for: projectName))
    }

    /// Create a new project directory with default structure.
    func createProject(named name: String) throws {
        let projectDir = projectDirectory(for: name)
        guard !fm.fileExists(atPath: projectDir.path) else {
            throw CodingError.alreadyExists
        }
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Sources/
        let sourcesDir = projectDir.appendingPathComponent("Sources")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        // Resources/
        let resourcesDir = projectDir.appendingPathComponent("Resources")
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    }

    /// Import a zip project by extracting into the Projects directory.
    func importProject(from zipURL: URL) throws -> URL {
        let projectName = zipURL.deletingPathExtension().lastPathComponent
        let projectDir = projectDirectory(for: projectName)
        guard !fm.fileExists(atPath: projectDir.path) else {
            throw CodingError.alreadyExists
        }
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        return projectDir
    }
}

// MARK: - Errors

enum CodingError: LocalizedError {
    case pathOutsideProject
    case alreadyExists
    case cannotDeleteRoot
    case encodingError
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .pathOutsideProject: return "Path is outside the project directory."
        case .alreadyExists: return "A file with that name already exists."
        case .cannotDeleteRoot: return "Cannot delete the project root directory."
        case .encodingError: return "Failed to decode file content as UTF-8."
        case .fileNotFound: return "File not found."
        }
    }
}
