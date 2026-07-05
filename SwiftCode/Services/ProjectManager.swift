import Foundation
import Combine

@MainActor
final class ProjectManager: ObservableObject {
    static let shared = ProjectManager()

    @Published var projects: [Project] = [] {
        didSet { persistProjectList() }
    }
    @Published var activeProject: Project?
    /// Backward-compatible alias used by older Assist code paths.
    var currentProject: Project? {
        get { activeProject }
        set { activeProject = newValue }
    }
    @Published var activeFileNode: FileNode?
    @Published var activeFileContent: String = ""

    private var autoSaveCancellable: AnyCancellable?
    private var pendingSave: DispatchWorkItem?
    private static let projectListKey = "com.swiftcode.projectList"

    // MARK: - Directories

    var projectsDirectory: URL {
        CodingManager.shared.projectsRoot
    }

    private func metadataURL(for project: Project) -> URL {
        projectsDirectory.appendingPathComponent(project.name).appendingPathComponent("project.json")
    }

    private init() {
        loadProjects()
    }

    // MARK: - UserDefaults Persistence

    /// Persist the project list to UserDefaults so the dashboard always shows projects.
    private func persistProjectList() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(projects) {
            UserDefaults.standard.set(data, forKey: Self.projectListKey)
        }
    }

    /// Load the project list from UserDefaults as a fallback when disk scan finds nothing.
    private func loadProjectListFromDefaults() -> [Project] {
        guard let data = UserDefaults.standard.data(forKey: Self.projectListKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Project].self, from: data)) ?? []
    }

    // MARK: - Load Projects

    func loadProjects() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            // If disk scan fails, restore from UserDefaults
            let cached = loadProjectListFromDefaults()
            if !cached.isEmpty { projects = cached }
            return
        }

        var loaded: [Project] = []
        for url in contents {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let metaURL = url.appendingPathComponent("project.json")
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let data = try? Data(contentsOf: metaURL),
               var project = try? decoder.decode(Project.self, from: data) {
                if project.ciBuildConfiguration == nil {
                    project.ciBuildConfiguration = CIBuildConfiguration()
                }
                if project.transferConfiguration == nil {
                    project.transferConfiguration = .owner
                }
                project.files = buildFileTree(at: url, relativeTo: url)
                loaded.append(project)
            } else {
                // Directory exists but has no project.json — create metadata so the project persists
                let name = url.lastPathComponent
                var project = Project(name: name)
                project.files = buildFileTree(at: url, relativeTo: url)
                try? saveMetadata(project)
                loaded.append(project)
            }
        }

        if loaded.isEmpty {
            // Fallback: try to recover from UserDefaults if disk is empty
            let cached = loadProjectListFromDefaults()
            projects = cached.sorted { $0.lastOpened > $1.lastOpened }
        } else {
            projects = loaded.sorted { $0.lastOpened > $1.lastOpened }
        }
    }

    // MARK: - Create Project

    func createProject(name: String) throws -> Project {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { throw ProjectError.invalidName }

        let projectDir = projectsDirectory.appendingPathComponent(sanitized)
        guard !FileManager.default.fileExists(atPath: projectDir.path) else {
            throw ProjectError.alreadyExists
        }

        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        var project = Project(name: sanitized)
        project.description = "A new SwiftCode project"
        project.transferConfiguration = .owner

        // Keep new projects empty so template selection can scaffold content later.

        // Rebuild file tree
        project.files = buildFileTree(at: projectDir, relativeTo: projectDir)

        // Persist metadata
        try saveMetadata(project)

        projects.insert(project, at: 0)
        return project
    }


    // MARK: - Delete Project

    func deleteProject(_ project: Project) throws {
        // First remove from file system
        try FileManager.default.removeItem(at: project.directoryURL)

        // Only update UI state after successful deletion
        projects.removeAll { $0.id == project.id }
        if activeProject?.id == project.id {
            activeProject = nil
            activeFileNode = nil
            activeFileContent = ""
            openFileTabs = []
        }
    }

    // MARK: - Rename Project

    func renameProject(_ project: Project, to newName: String) throws {
        let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { throw ProjectError.invalidName }

        let newURL = projectsDirectory.appendingPathComponent(sanitized)
        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw ProjectError.alreadyExists
        }

        try FileManager.default.moveItem(at: project.directoryURL, to: newURL)

        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].name = sanitized
            try saveMetadata(projects[idx])
        }

        if activeProject?.id == project.id {
            activeProject?.name = sanitized
        }
    }

    // MARK: - Duplicate Project

    func duplicateProject(_ project: Project) throws -> Project {
        let baseName = "\(project.name) Copy"
        var newName = baseName
        var counter = 2
        while FileManager.default.fileExists(atPath: projectsDirectory.appendingPathComponent(newName).path) {
            newName = "\(baseName) \(counter)"
            counter += 1
        }

        let newURL = projectsDirectory.appendingPathComponent(newName)
        try FileManager.default.copyItem(at: project.directoryURL, to: newURL)

        var newProject = Project(name: newName)
        newProject.description = project.description
        newProject.transferConfiguration = project.transferConfiguration
        newProject.files = buildFileTree(at: newURL, relativeTo: newURL)
        try saveMetadata(newProject)

        projects.insert(newProject, at: 0)
        return newProject
    }

    // MARK: - Open / Close Project

    func openProject(_ project: Project) {
        var updated = project
        updated.lastOpened = Date()
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = updated
            try? saveMetadata(projects[idx])
        }
        updated.files = buildFileTree(at: updated.directoryURL, relativeTo: updated.directoryURL)
        activeProject = updated
        activeFileNode = nil
        activeFileContent = ""
    }

    func closeProject() {
        activeProject = nil
        activeFileNode = nil
        activeFileContent = ""
        openFileTabs = []
        fileLoadError = nil
    }

    // MARK: - File Operations

    @Published var fileLoadError: String?
    @Published var openFileTabs: [FileNode] = []
    @Published var modifiedFilePaths: Set<String> = []

    private var currentFileLoadTask: Task<Void, Never>?

    func openFile(_ node: FileNode) {
        guard !node.isDirectory else { return }
        guard let project = activeProject else { return }

        // Cancel any in-flight file load to prevent race conditions
        currentFileLoadTask?.cancel()

        fileLoadError = nil
        activeFileNode = node

        // Add to open tabs if not already present
        if !openFileTabs.contains(where: { $0.id == node.id }) {
            openFileTabs.append(node)
        }

        // Use CodeReaderManager to resolve the path relative to the Projects directory.
        // This ensures correct path resolution after ZIP import or GitHub import, regardless
        // of how the FileNode path was originally stored.
        let projectName = project.name
        let relativePath = node.path
        let nodeName = node.name
        let nodeId = node.id

        currentFileLoadTask = Task { @MainActor in
            do {
                let content = try await CodeReaderManager.shared.readFileAsync(
                    project: projectName,
                    relativePath: relativePath
                )
                // Only update if this node is still the active one (user didn't switch away)
                guard self.activeFileNode?.id == nodeId else { return }
                self.activeFileContent = content
                self.fileLoadError = nil
            } catch {
                // Only update error if this node is still the active one
                guard self.activeFileNode?.id == nodeId else { return }
                self.activeFileContent = ""
                self.fileLoadError = "Failed to load \(nodeName): \(error.localizedDescription)"
            }
        }
    }

    func closeTab(_ node: FileNode) {
        openFileTabs.removeAll { $0.id == node.id }
        if activeFileNode?.id == node.id {
            if let last = openFileTabs.last {
                openFile(last)
            } else {
                activeFileNode = nil
                activeFileContent = ""
            }
        }
    }

    func saveCurrentFile(content: String) {
        guard let project = activeProject,
              let node = activeFileNode else { return }
        do {
            try CodingManager.shared.writeFile(content: content, at: node.path, in: project.directoryURL)
            activeFileContent = content
            modifiedFilePaths.remove(node.path)
            fileLoadError = nil
        } catch {
            // Keep the modified state and show error to user
            fileLoadError = "Failed to save \(node.name): \(error.localizedDescription)"
        }
    }

    func markFileModified(path: String) {
        modifiedFilePaths.insert(path)
    }

    func createFile(named name: String, inDirectory directoryPath: String?, project: Project, initialContent: String? = nil) throws {
        let content: String
        if let provided = initialContent {
            content = provided
        } else if name.hasSuffix(".swift") {
            content = generateSwiftTemplate(for: name, in: project)
        } else {
            content = ""
        }
        try CodingManager.shared.createFile(named: name, at: directoryPath, in: project.directoryURL, content: content)
        refreshFileTree(for: project)
    }

    private func generateSwiftTemplate(for name: String, in project: Project) -> String {
        let settings = AppSettings.shared
        let rawName = (name as NSString).deletingPathExtension
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        // Ensure the struct name starts with a letter (Swift identifier requirement)
        let structName: String
        if rawName.isEmpty || rawName.first?.isLetter == false {
            structName = "UntitledView"
        } else {
            structName = rawName
        }
        let author = settings.fileHeaderAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorDisplay = author.isEmpty ? "User" : author
        let customComment = settings.fileHeaderCustomComment.trimmingCharacters(in: .whitespacesAndNewlines)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
        let dateStr = dateFormatter.string(from: Date())

        return """
//  \(name)
//  \(project.name)
//
//  Created by \(authorDisplay) on \(dateStr).
//  \(customComment.isEmpty ? "Made with SwiftCode" : customComment)
//

import SwiftUI

struct \(structName): View {
    var body: some View {
        VStack {
            Text("Hello, World!")
        }
        .padding()
    }
}

#Preview {
    \(structName)()
}
"""
    }

    func createFolder(named name: String, inDirectory directoryPath: String?, project: Project) throws {
        try CodingManager.shared.createDirectory(named: name, at: directoryPath, in: project.directoryURL)
        refreshFileTree(for: project)
    }

    func deleteNode(_ node: FileNode, project: Project) throws {
        try CodingManager.shared.deleteItem(at: node.path, in: project.directoryURL)
        if activeFileNode?.id == node.id {
            activeFileNode = nil
            activeFileContent = ""
        }
        refreshFileTree(for: project)
    }

    func renameNode(_ node: FileNode, to newName: String, project: Project) throws {
        try CodingManager.shared.renameItem(at: node.path, to: newName, in: project.directoryURL)
        refreshFileTree(for: project)
    }



    func rebuildFileTree(at directoryURL: URL) -> [FileNode] {
        buildFileTree(at: directoryURL, relativeTo: directoryURL)
    }

    func saveImportedProject(_ project: Project) throws {
        try saveMetadata(project)
        projects.insert(project, at: 0)
    }

    func updateDescription(_ description: String, for project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].description = description
        if activeProject?.id == project.id { activeProject?.description = description }
        try? saveMetadata(projects[index])
    }

    func updateTransferConfiguration(_ configuration: ProjectTransferConfiguration, for project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].transferConfiguration = configuration
        if activeProject?.id == project.id { activeProject?.transferConfiguration = configuration }
        try? saveMetadata(projects[index])
    }

    func recordTransferAudit(for project: Project, actor: String, action: String, path: String?, allowed: Bool, detail: String) {
        var configuration = project.transferConfiguration ?? .owner
        configuration.auditLog.append(TransferAuditEntry(actor: actor, action: action, path: path, allowed: allowed, detail: detail))
        updateTransferConfiguration(configuration, for: project)
    }

    // MARK: - File Tree

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

    func updateCIBuildConfiguration(_ configuration: CIBuildConfiguration, for project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx].ciBuildConfiguration = configuration
        try? saveMetadata(projects[idx])

        if activeProject?.id == project.id {
            activeProject?.ciBuildConfiguration = configuration
        }
    }

    func refreshFileTree(for project: Project) {
        let files = buildFileTree(at: project.directoryURL, relativeTo: project.directoryURL)
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].files = files
        }
        if activeProject?.id == project.id {
            activeProject?.files = files
        }
    }

    // MARK: - Metadata Persistence

    private func saveMetadata(_ project: Project) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: metadataURL(for: project))
    }
}

// MARK: - Errors

enum ProjectError: LocalizedError {
    case invalidName
    case alreadyExists
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Project name is invalid."
        case .alreadyExists: return "A project with that name already exists."
        case .notFound: return "Project not found."
        }
    }
}
