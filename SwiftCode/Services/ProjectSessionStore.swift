import Foundation
import Observation
import os.log
import SwiftUI

enum ProjectOpeningState: Equatable {
    case idle
    case resolving
    case loading(progress: Double, projectName: String)
    case ready(Project)
    case failed(ProjectOpenError)
    case cancelled

    static func == (lhs: ProjectOpeningState, rhs: ProjectOpeningState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.resolving, .resolving): return true
        case (.loading(let lp, let ln), .loading(let rp, let rn)): return lp == rp && ln == rn
        case (.ready(let lp), .ready(let rp)): return lp.id == rp.id
        case (.failed(let le), .failed(let re)): return le.localizedDescription == re.localizedDescription
        case (.cancelled, .cancelled): return true
        default: return false
        }
    }
}

@Observable
@MainActor
final class ProjectSessionStore {
    static let shared = ProjectSessionStore()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectSession")
    private let coordinator = ProjectOpeningCoordinator()
    private static let projectListKey = "com.swiftcode.projectList"
    private let fm = FileManager.default

    var state: ProjectOpeningState = .idle
    var projects: [Project] = [] {
        didSet { persistProjectList() }
    }

    var activeProject: Project? {
        if case .ready(let project) = state {
            return project
        }
        return nil
    }

    var activeFileNode: FileNode?
    var activeFileContent: String = ""
    var openFileTabs: [FileNode] = []
    var modifiedFilePaths: Set<String> = []
    var fileLoadError: String?

    // MARK: - Initializer

    init() {
        loadProjects()
    }

    // MARK: - Library Management

    var projectsDirectory: URL {
        CodingManager.shared.projectsRoot
    }

    private func persistProjectList() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(projects) {
            UserDefaults.standard.set(data, forKey: Self.projectListKey)
        }
    }

    func loadProjects() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else {
            // Fallback to UserDefaults
            guard let data = UserDefaults.standard.data(forKey: Self.projectListKey) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            self.projects = (try? decoder.decode([Project].self, from: data)) ?? []
            if projects.isEmpty {
                scaffoldIntroProjectIfNeeded()
            }
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
                loaded.append(project)
            } else {
                let name = url.lastPathComponent
                let project = Project(name: name)
                try? saveMetadata(project)
                loaded.append(project)
            }
        }

        if loaded.isEmpty {
             scaffoldIntroProjectIfNeeded()
        } else {
            self.projects = loaded.sorted { $0.lastOpened > $1.lastOpened }
        }
    }

    private func scaffoldIntroProjectIfNeeded() {
        let introName = "Introduction"
        let introURL = projectsDirectory.appendingPathComponent(introName)

        guard !fm.fileExists(atPath: introURL.path) else { return }

        Task {
            do {
                try await ProjectScaffoldTemplateEngine.shared.createProject(at: introURL, template: IntroductionTemplate())
                let project = try loadOrCreateProject(at: introURL)
                await MainActor.run {
                    if !self.projects.contains(where: { $0.name == introName }) {
                        self.projects.insert(project, at: 0)
                    }
                }
            } catch {
                logger.error("Failed to scaffold intro project: \(error.localizedDescription)")
            }
        }
    }

    func updateProjectSettings(description: String, githubRepo: String?, for project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].description = description
            projects[idx].githubRepo = githubRepo
            saveMetadata(projects[idx])
        }
        if activeProject?.id == project.id {
            if case .ready(var p) = state {
                p.description = description
                p.githubRepo = githubRepo
                state = .ready(p)
            }
        }
    }

    // MARK: - Session Actions

    private var openingTask: Task<Void, Never>?

    func openProject(_ project: Project) async {
        openingTask?.cancel()
        openingTask = Task {
            guard !Task.isCancelled else { return }

            state = .resolving
            logger.info("Opening project: \(project.name)")

            do {
                let loadedProject = try await coordinator.loadProjectWithTimeout(url: project.directoryURL)
                if Task.isCancelled { return }

                state = .ready(loadedProject)

                // Update last opened date in library
                if let idx = projects.firstIndex(where: { $0.id == project.id }) {
                    var updated = projects[idx]
                    updated.lastOpened = Date()
                    projects[idx] = updated
                    saveMetadata(updated)
                }
            } catch let error as ProjectOpenError {
                state = .failed(error)
            } catch is CancellationError {
                state = .cancelled
            } catch {
                state = .failed(.underlyingIO(error))
            }
        }
    }

    func closeProject() {
        openingTask?.cancel()
        state = .idle
        activeFileNode = nil
        activeFileContent = ""
        openFileTabs = []
        modifiedFilePaths = []
        fileLoadError = nil
    }

    func retryLoad(for project: Project) async {
        state = .idle
        await openProject(project)
    }

    func cancelLoad() {
        openingTask?.cancel()
        state = .cancelled
    }

    // MARK: - CRUD Operations

    func createProject(name: String) throws -> Project {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { throw ProjectOpenError.pathNotFound } // Reusing or should define specific CRUD errors

        let projectDir = projectsDirectory.appendingPathComponent(sanitized)
        guard !fm.fileExists(atPath: projectDir.path) else {
            throw ProjectOpenError.underlyingIO(NSError(domain: "SwiftCode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project already exists"]))
        }

        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        var project = Project(name: sanitized)
        project.description = "A new SwiftCode project"
        project.transferConfiguration = .owner

        try saveMetadata(project)
        projects.insert(project, at: 0)
        return project
    }

    func deleteProject(_ project: Project) throws {
        try fm.removeItem(at: project.directoryURL)
        projects.removeAll { $0.id == project.id }
        if activeProject?.id == project.id {
            closeProject()
        }
    }

    func renameProject(_ project: Project, to newName: String) throws {
        let sanitized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }

        let newURL = projectsDirectory.appendingPathComponent(sanitized)
        guard !fm.fileExists(atPath: newURL.path) else { return }

        try fm.moveItem(at: project.directoryURL, to: newURL)

        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].name = sanitized
            saveMetadata(projects[idx])
        }

        if activeProject?.id == project.id {
            if case .ready(var p) = state {
                p.name = sanitized
                state = .ready(p)
            }
        }
    }

    func duplicateProject(_ project: Project) throws -> Project {
        let baseName = "\(project.name) Copy"
        var newName = baseName
        var counter = 2
        while fm.fileExists(atPath: projectsDirectory.appendingPathComponent(newName).path) {
            newName = "\(baseName) \(counter)"
            counter += 1
        }

        let newURL = projectsDirectory.appendingPathComponent(newName)
        try fm.copyItem(at: project.directoryURL, to: newURL)

        var newProject = Project(name: newName)
        newProject.description = project.description
        newProject.transferConfiguration = project.transferConfiguration
        try saveMetadata(newProject)

        projects.insert(newProject, at: 0)
        return newProject
    }

    func importProject(from url: URL) async throws -> Project {
        let name = url.lastPathComponent
        let destinationURL = projectsDirectory.appendingPathComponent(name)

        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        if url.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            let project = try loadOrCreateProject(at: url)
            if !projects.contains(where: { $0.id == project.id }) {
                projects.insert(project, at: 0)
            }
            return project
        }

        if fm.fileExists(atPath: destinationURL.path) {
            throw ProjectOpenError.underlyingIO(NSError(domain: "SwiftCode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project already exists"]))
        }

        try fm.copyItem(at: url, to: destinationURL)
        let project = try loadOrCreateProject(at: destinationURL)
        projects.insert(project, at: 0)
        return project
    }

    private func loadOrCreateProject(at url: URL) throws -> Project {
        let metaURL = url.appendingPathComponent("project.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: metaURL),
           var project = try? decoder.decode(Project.self, from: data) {
            return project
        } else {
            let name = url.lastPathComponent
            let project = Project(name: name)
            try saveMetadata(project)
            return project
        }
    }

    // MARK: - File Operations

    private var currentFileLoadTask: Task<Void, Never>?

    func openFile(_ node: FileNode) {
        guard !node.isDirectory else { return }
        guard let project = activeProject else { return }

        currentFileLoadTask?.cancel()
        fileLoadError = nil
        activeFileNode = node

        if !openFileTabs.contains(where: { $0.id == node.id }) {
            openFileTabs.append(node)
        }

        let projectName = project.name
        let relativePath = node.path
        let nodeId = node.id

        currentFileLoadTask = Task {
            do {
                let content = try await CodeReaderManager.shared.readFileAsync(
                    project: projectName,
                    relativePath: relativePath
                )
                guard !Task.isCancelled, self.activeFileNode?.id == nodeId else { return }
                self.activeFileContent = content
            } catch {
                guard !Task.isCancelled, self.activeFileNode?.id == nodeId else { return }
                self.activeFileContent = ""
                self.fileLoadError = "Failed to load: \(error.localizedDescription)"
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
        guard let project = activeProject, let node = activeFileNode else { return }
        do {
            try CodingManager.shared.writeFile(content: content, at: node.path, in: project.directoryURL)
            activeFileContent = content
            modifiedFilePaths.remove(node.path)
            fileLoadError = nil
        } catch {
            fileLoadError = "Failed to save: \(error.localizedDescription)"
        }
    }

    func saveAll() {
        // Implementation for saving all open modified files
        for node in openFileTabs {
            if modifiedFilePaths.contains(node.path) {
                // In a real scenario we'd need the content for each tab.
                // Assuming activeFileContent is for activeFileNode.
                if node.id == activeFileNode?.id {
                    saveCurrentFile(content: activeFileContent)
                }
            }
        }
    }

    func markFileModified(path: String) {
        modifiedFilePaths.insert(path)
    }

    func createFile(named name: String, inDirectory directoryPath: String?, project: Project, initialContent: String? = nil) throws {
        let content = initialContent ?? (name.hasSuffix(".swift") ? generateSwiftTemplate(for: name, in: project) : "")
        try CodingManager.shared.createFile(named: name, at: directoryPath, in: project.directoryURL, content: content)
        refreshFileTree(for: project)
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

    func updateCIBuildConfiguration(_ configuration: CIBuildConfiguration, for project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].ciBuildConfiguration = configuration
            saveMetadata(projects[idx])
        }
        if activeProject?.id == project.id {
            if case .ready(var p) = state {
                p.ciBuildConfiguration = configuration
                state = .ready(p)
            }
        }
    }

    func refreshFileTree(for project: Project) {
        Task {
            let files = (try? await coordinator.buildFileTreeInternal(at: project.directoryURL, relativeTo: project.directoryURL)) ?? []
            if let idx = projects.firstIndex(where: { $0.id == project.id }) {
                projects[idx].files = files
            }
            if activeProject?.id == project.id {
                if case .ready(var p) = state {
                    p.files = files
                    state = .ready(p)
                }
            }
        }
    }

    func rebuildFileTree(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let basePath = url.standardizedFileURL.path

        let metadataFiles = [
            "manifest.json", "metadata.json", "integrity.json",
            "version.json", "project.json", "project.xml", "project.plist"
        ]

        var nodes: [FileNode] = []

        for childURL in contents {
            if metadataFiles.contains(childURL.lastPathComponent) { continue }

            let resourceValues = try? childURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false
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

    func saveImportedProject(_ project: Project) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let metaURL = project.directoryURL.appendingPathComponent("project.json")
        try data.write(to: metaURL, options: .atomic)

        if !projects.contains(where: { $0.id == project.id }) {
            projects.insert(project, at: 0)
        }
    }

    // MARK: - Helpers

    private func saveMetadata(_ project: Project) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(project) {
            let metaURL = project.directoryURL.appendingPathComponent("project.json")
            try? data.write(to: metaURL)
        }
    }

    private func generateSwiftTemplate(for name: String, in project: Project) -> String {
        let settings = AppSettings.shared
        let rawName = (name as NSString).deletingPathExtension
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        let structName = (rawName.isEmpty || rawName.first?.isLetter == false) ? "UntitledView" : rawName
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
}
