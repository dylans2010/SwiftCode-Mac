import Foundation
import Observation

@MainActor
@Observable
public final class CodingManager {
    public static let shared = CodingManager()

    private let fm = FileManager.default

    var projectsRoot: URL {
        let useCustom = UserDefaults.standard.bool(forKey: "saveProjectsOnCustomFolder")
        if useCustom {
            let customPath = UserDefaults.standard.string(forKey: "customProjectsFolder") ?? ""
            if !customPath.isEmpty {
                return URL(fileURLWithPath: customPath)
            }
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects")
    }

    var modelsRoot: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        modelsRoot = docs.appendingPathComponent("Models")

        let useCustom = UserDefaults.standard.bool(forKey: "saveProjectsOnCustomFolder")
        var currentProjectsRoot = docs.appendingPathComponent("Projects")
        if useCustom {
            let customPath = UserDefaults.standard.string(forKey: "customProjectsFolder") ?? ""
            if !customPath.isEmpty {
                currentProjectsRoot = URL(fileURLWithPath: customPath)
            }
        }
        try? FileManager.default.createDirectory(at: currentProjectsRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
    }

    public func ensureProjectsDirectory() {
        if !fm.fileExists(atPath: projectsRoot.path) {
            try? fm.createDirectory(at: projectsRoot, withIntermediateDirectories: true)
        }
    }

    public func ensureModelsDirectory() {
        if !fm.fileExists(atPath: modelsRoot.path) {
            try? fm.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        }
    }

    public func listModels() -> [URL] {
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

    public func importModel(from sourceURL: URL) throws -> URL {
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

    public func deleteModel(named name: String) throws {
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

    func readFile(at relativePath: String, in projectDir: URL) throws -> String {
        let url = projectDir.appendingPathComponent(relativePath)
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        return try String(contentsOf: standardized, encoding: .utf8)
    }

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

    func writeFile(content: String, at relativePath: String, in projectDir: URL) throws {
        let url = projectDir.appendingPathComponent(relativePath)
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        let projectStd = projectDir.standardizedFileURL.resolvingSymlinksInPath()
        guard standardized.path.hasPrefix(projectStd.path + "/") || standardized.path == projectStd.path else {
            throw CodingError.pathOutsideProject
        }
        let parent = standardized.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        try content.write(to: standardized, atomically: true, encoding: .utf8)
    }

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
        try content.write(to: standardized, atomically: true, encoding: .utf8)
    }

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

    func fileExists(at relativePath: String, in projectDir: URL) -> Bool {
        let url = projectDir.appendingPathComponent(relativePath)
        return fm.fileExists(atPath: url.standardizedFileURL.path)
    }

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

    func projectDirectory(for projectName: String) -> URL {
        projectsRoot.appendingPathComponent(projectName)
    }

    func readFile(at relativePath: String, in project: String) throws -> String {
        try readFile(at: relativePath, in: projectDirectory(for: project))
    }

    func writeFile(content: String, to relativePath: String, in project: String) throws {
        try writeFile(content: content, at: relativePath, in: projectDirectory(for: project))
    }

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
            try "".write(to: standardized, atomically: true, encoding: .utf8)
        }
    }

    func deleteFile(at relativePath: String, in project: String) throws {
        try deleteItem(at: relativePath, in: projectDirectory(for: project))
    }

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

    func deleteFolder(at relativePath: String, in project: String) throws {
        try deleteItem(at: relativePath, in: projectDirectory(for: project))
    }

    func scanProject(projectName: String) -> [String] {
        scanProjectFiles(in: projectDirectory(for: projectName))
    }

    func createProject(named name: String) throws {
        let projectDir = projectDirectory(for: name)
        guard !fm.fileExists(atPath: projectDir.path) else {
            throw CodingError.alreadyExists
        }
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let sourcesDir = projectDir.appendingPathComponent("Sources")
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let resourcesDir = projectDir.appendingPathComponent("Resources")
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
    }

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
