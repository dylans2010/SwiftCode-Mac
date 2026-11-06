// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/ProjectSessionStore.swift (Legacy main ab03f681)
//
// Destination: SwiftCodeIDECore/Model/ProjectSessionStore.swift.
//
// The store's missing coordinator methods are ported alongside it in
// `Session/ProjectOpeningCoordinator+LegacyLoad.swift` (same target):
// the landed `ProjectOpeningCoordinator` opens `WorkspaceSession`s and
// has no `loadProjectWithTimeout(url:)` / `buildFileTreeInternal(at:)`,
// so those two Legacy coordinator methods land as an extension there
// rather than being re-implemented here.
//
// Adaptations (behaviour preserved unless noted):
// * Access raised deliberately: Legacy's store was internal in a
//   single-module app; in the destination its callers live in other
//   targets (`SwiftCodeAssistant`, `SwiftCodeIDEShell`, `SwiftCodeUI`,
//   `swiftcode-ide`), so the class is `public` and every member those
//   call sites use is public (see DISPOSITIONS.md for the member list).
//   Only the genuinely internal machinery stays private: `logger`,
//   `fm`, `coordinator`, `sessions`, `openingTask`,
//   `currentFileLoadTask`, `persistProjectList`,
//   `scaffoldIntroProjectIfNeeded`, `loadOrCreateProject`,
//   `refreshSwiftCodeSessionJSONCopy`,
//   `refreshSwiftCodeProjectJSONCopy`, `saveMetadata`, `readFileContent`,
//   `decodeText`, `generateSwiftTemplate`. `init()` stays internal;
//   `shared` is the access point.
// * `import SwiftUI` dropped (no SwiftUI type is used in this file);
//   `import SwiftCodeAssistant` added (`AppSettings`),
//   `import SwiftCodeProject` added (`PBXProj`),
//   `import SwiftCodeWorkspace` added (`Scheme`). All three are already
//   dependencies of SwiftCodeIDECore in Package.swift.
// * The nested `AssistFileDiff` is NOT redefined: it already exists at
//   top level in this module as `AssistSessionFileDiff`
//   (`Model/ProjectTrustAndDiff.swift`, same shape, same memberwise init)
//   and the store's properties and `recordAssistFileMutation` use that
//   type verbatim. (Renamed from `AssistFileDiff` by fixes-jsonvalue:
//   `SwiftCodeAssistant` defines a snapshot `AssistFileDiff` of a
//   different shape; see staging-wire/fixes-jsonvalue/DISPOSITIONS.md.)
// * The nested `ScprojTrustStore` is NOT redefined: the single
//   definition lives in `SwiftCodeIDEShell/ScprojTrustStore.swift`
//   (identical API) and the store never calls it internally. (The
//   duplicate copy that used to live at top level in this module was
//   removed — see `Model/ProjectTrustAndDiff.swift` header.)
// * `ensureSwiftCodeJSON` no longer constructs `SDKManifest`: that type
//   lives in SwiftCodeExtensions as the renamed `SwiftCodeManifest`,
//   which SwiftCodeIDECore does not depend on — and the Extensions
//   type would emit the same keys for this input, so instead the
//   manifest is written by private nested Codable structs at the foot
//   of this file (`SwiftCodeManifestJSON` et al.) that mirror Legacy's
//   `SDKManifest` shape exactly and are encoded with the same
//   `JSONEncoder` settings Legacy used (`.prettyPrinted, .sortedKeys`,
//   no `.withoutEscapingSlashes`), so the bytes written to
//   `swiftcode.json` are unchanged.
// * `importProject` no longer calls `XcodeBuildAPI` / `XcodeProjParse`:
//   - `XcodeBuildAPI` has no definition anywhere — not in Legacy, not
//     on main — so there is nothing to port. Scheme discovery uses the
//     destination-native equivalent: the imported root's own `.xcscheme`
//     files (`Scheme.discover(in:)`, SwiftCodeWorkspace), falling back
//     to `[name]` exactly as Legacy's `?? [name]` did.
//   - `XcodeProjParse` (Legacy, 552 lines, its own PBX model) is
//     replaced by the destination's own pbxproj parser, `PBXProj`
//     (SwiftCodeProject): `targets` for target names and the
//     `XCBuildConfiguration` objects for the first
//     `PRODUCT_BUNDLE_IDENTIFIER`, the same lookup Legacy did
//     (`DestinationMenu.swift` uses the identical access shape).
//   See DISPOSITIONS.md for both.
// * `openProject` still calls
//   `LocalizationCore.shared.scanProjectFiles(projectURL:)` verbatim.
//   `LocalizationCore` now exists on main (SwiftCodeIDECore/Model/
//   LocalizationCore.swift, ported from Legacy's 488-line file).
// * `decodeText` is a `private static func` (was an instance method):
//   `readFileContent` calls it from a detached task, and a detached
//   task must not capture the MainActor-isolated store under Swift 6
//   strict concurrency. The function is pure, so this changes no
//   behaviour.
// * `ProjectOpenError` is the top-level type in this module
//   (`Model/ProjectOpenError.swift`) — reused, not redefined. Note the
//   landed `ProjectOpeningCoordinator` also declares a *nested*
//   `ProjectOpenError` with different cases; the two types are
//   unrelated and the store only ever uses the top-level one.

import Foundation
import Observation
import os.log
import SwiftCodeAssistant
import SwiftCodeProject
import SwiftCodeWorkspace

public enum ProjectOpeningState: Equatable {
    case idle
    case resolving
    case loading(progress: Double, projectName: String)
    case ready(Project)
    case failed(ProjectOpenError)
    case cancelled

    public static func == (lhs: ProjectOpeningState, rhs: ProjectOpeningState) -> Bool {
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
public final class ProjectSession: Codable, @unchecked Sendable {
    public let id: UUID // matches project.id
    public var projectRootPath: String
    public var activeFileNode: FileNode?
    public var activeFileContent: String = ""
    public var openFileTabs: [FileNode] = []
    public var modifiedFilePaths: Set<String> = []
    public var fileLoadError: String?

    // Editor State
    public var cursorPosition: Int = 0
    public var scrollPosition: Double = 0.0
    public var selectionRangeText: String? // Codable representation of NSRange
    public var foldingState: [String: Bool] = [:]

    // Navigation State
    public var expandedNodeIDs: Set<String> = []
    public var selectedNodeID: String?
    public var lastOpenedFile: String?
    public var lastActiveTab: String?
    public var sidebarSelection: String?
    public var showFileNavigator: Bool = true
    public var showArtboardSimulator: Bool = false
    public var showAgentInspector: Bool = false
    public var showAppDetailsSidebar: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, projectRootPath, activeFileNode, openFileTabs, modifiedFilePaths, cursorPosition, scrollPosition, selectionRangeText, foldingState,
             expandedNodeIDs, selectedNodeID, lastOpenedFile, lastActiveTab, sidebarSelection, showFileNavigator, showArtboardSimulator, showAgentInspector, showAppDetailsSidebar
    }

    public init(id: UUID, projectRootPath: String) {
        self.id = id
        self.projectRootPath = projectRootPath
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectRootPath = try container.decode(String.self, forKey: .projectRootPath)
        activeFileNode = try container.decodeIfPresent(FileNode.self, forKey: .activeFileNode)
        openFileTabs = try container.decodeIfPresent([FileNode].self, forKey: .openFileTabs) ?? []
        let modifiedPathsArray = try container.decodeIfPresent([String].self, forKey: .modifiedFilePaths) ?? []
        modifiedFilePaths = Set(modifiedPathsArray)
        cursorPosition = try container.decodeIfPresent(Int.self, forKey: .cursorPosition) ?? 0
        scrollPosition = try container.decodeIfPresent(Double.self, forKey: .scrollPosition) ?? 0.0
        selectionRangeText = try container.decodeIfPresent(String.self, forKey: .selectionRangeText)
        foldingState = try container.decodeIfPresent([String: Bool].self, forKey: .foldingState) ?? [:]

        // Decode navigation states with default fallbacks
        let expandedArr = try container.decodeIfPresent([String].self, forKey: .expandedNodeIDs) ?? []
        expandedNodeIDs = Set(expandedArr)
        selectedNodeID = try container.decodeIfPresent(String.self, forKey: .selectedNodeID)
        lastOpenedFile = try container.decodeIfPresent(String.self, forKey: .lastOpenedFile)
        lastActiveTab = try container.decodeIfPresent(String.self, forKey: .lastActiveTab)
        sidebarSelection = try container.decodeIfPresent(String.self, forKey: .sidebarSelection)
        showFileNavigator = try container.decodeIfPresent(Bool.self, forKey: .showFileNavigator) ?? true
        showArtboardSimulator = try container.decodeIfPresent(Bool.self, forKey: .showArtboardSimulator) ?? false
        showAgentInspector = try container.decodeIfPresent(Bool.self, forKey: .showAgentInspector) ?? false
        showAppDetailsSidebar = try container.decodeIfPresent(Bool.self, forKey: .showAppDetailsSidebar) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectRootPath, forKey: .projectRootPath)
        try container.encode(activeFileNode, forKey: .activeFileNode)
        try container.encode(openFileTabs, forKey: .openFileTabs)
        try container.encode(Array(modifiedFilePaths), forKey: .modifiedFilePaths)
        try container.encode(cursorPosition, forKey: .cursorPosition)
        try container.encode(scrollPosition, forKey: .scrollPosition)
        try container.encode(selectionRangeText, forKey: .selectionRangeText)
        try container.encode(foldingState, forKey: .foldingState)

        // Encode navigation states
        try container.encode(Array(expandedNodeIDs), forKey: .expandedNodeIDs)
        try container.encode(selectedNodeID, forKey: .selectedNodeID)
        try container.encode(lastOpenedFile, forKey: .lastOpenedFile)
        try container.encode(lastActiveTab, forKey: .lastActiveTab)
        try container.encode(sidebarSelection, forKey: .sidebarSelection)
        try container.encode(showFileNavigator, forKey: .showFileNavigator)
        try container.encode(showArtboardSimulator, forKey: .showArtboardSimulator)
        try container.encode(showAgentInspector, forKey: .showAgentInspector)
        try container.encode(showAppDetailsSidebar, forKey: .showAppDetailsSidebar)
    }
}

@Observable
@MainActor
public final class ProjectSessionStore {
    public static let shared = ProjectSessionStore()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectSession")
    private let coordinator = ProjectOpeningCoordinator()
    private static let projectListKey = "com.swiftcode.projectList"
    private let fm = FileManager.default

    public var state: ProjectOpeningState = .idle
    public var projects: [Project] = [] {
        didSet { persistProjectList() }
    }

    public var activeProject: Project? {
        if case .ready(let project) = state {
            return project
        }
        return nil
    }

    // Active session reference
    public var activeSession: ProjectSession?

    // Store all sessions in memory
    private var sessions: [UUID: ProjectSession] = [:]

    public var activeFileNode: FileNode? {
        get { activeSession?.activeFileNode }
        set { activeSession?.activeFileNode = newValue }
    }
    public var activeFileContent: String {
        get { activeSession?.activeFileContent ?? "" }
        set { activeSession?.activeFileContent = newValue }
    }
    public var openFileTabs: [FileNode] {
        get { activeSession?.openFileTabs ?? [] }
        set { activeSession?.openFileTabs = newValue }
    }
    public var modifiedFilePaths: Set<String> {
        get { activeSession?.modifiedFilePaths ?? [] }
        set { activeSession?.modifiedFilePaths = newValue }
    }
    public var fileLoadError: String? {
        get { activeSession?.fileLoadError }
        set { activeSession?.fileLoadError = newValue }
    }

    // MARK: - Assist File Mutation & Diff Presentation

    // `AssistSessionFileDiff` is the top-level type in `Model/ProjectTrustAndDiff.swift`
    // (Legacy's nested struct, ported there by batch A2) — not redefined here.

    public var activeFileDiff: AssistSessionFileDiff? = nil
    public var showDiffBanner: Bool = false

    // MARK: - Initializer

    init() {
        loadProjects()
    }

    public func getOrCreateSession(for project: Project) -> ProjectSession {
        if let existing = sessions[project.id] {
            return existing
        }
        // SwiftCode/session.json is the open-time copy (see
        // ensureSwiftCodeMetadataOnOpen); the root session.json is
        // kept as the fallback so projects opened before SwiftCode/
        // existed still resume exactly where they left off.
        let candidates = [
            project.directoryURL.appendingPathComponent("SwiftCode/session.json"),
            project.directoryURL.appendingPathComponent("session.json"),
        ]
        for sessionURL in candidates {
            if let data = try? Data(contentsOf: sessionURL),
               let session = try? JSONDecoder().decode(ProjectSession.self, from: data) {
                sessions[project.id] = session
                return session
            }
        }
        let session = ProjectSession(id: project.id, projectRootPath: project.directoryURL.path)
        sessions[project.id] = session
        return session
    }

    public func saveSession(_ session: ProjectSession) {
        let sessionURL = URL(fileURLWithPath: session.projectRootPath).appendingPathComponent("session.json")
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: sessionURL, options: .atomic)
            refreshSwiftCodeSessionJSONCopy(session: session, data: data)
        }
    }

    /// Keeps the SwiftCode/session.json copy in sync when the
    /// project has a SwiftCode/ directory. Best-effort: the root
    /// session.json is the source of truth, and a failed copy must
    /// never fail a save.
    private func refreshSwiftCodeSessionJSONCopy(session: ProjectSession, data: Data) {
        let dir = URL(fileURLWithPath: session.projectRootPath).appendingPathComponent("SwiftCode")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return }
        try? data.write(to: dir.appendingPathComponent("session.json"), options: .atomic)
    }

    // MARK: - Library Management

    public var projectsDirectory: URL {
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

        // 1. Load from UserDefaults
        var loaded: [Project] = []
        if let data = UserDefaults.standard.data(forKey: Self.projectListKey) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([Project].self, from: data) {
                // Verify each project still exists on disk
                for project in decoded {
                    if fm.fileExists(atPath: project.directoryURL.path) {
                        loaded.append(project)
                    }
                }
            }
        }

        // 2. Also scan projectsDirectory (default or custom save directory) to find any untracked project folders
        if let contents = try? fm.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for url in contents {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

                // Skip if already loaded
                if loaded.contains(where: {
                    $0.directoryURL.standardizedFileURL.path == url.standardizedFileURL.path
                }) {
                    continue
                }

                let metaURL = url.appendingPathComponent("project.json")
                if let data = try? Data(contentsOf: metaURL),
                   let project = try? decoder.decode(Project.self, from: data) {
                    loaded.append(project)
                } else {
                    let name = url.lastPathComponent
                    let project = Project(name: name)
                    try? saveMetadataInPlace(project)
                    loaded.append(project)
                }
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

    public func updateProjectDestinations(_ destinations: [String], for project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].destinations = destinations
            saveMetadata(projects[idx])
        }
        if activeProject?.id == project.id {
            if case .ready(var p) = state {
                p.destinations = destinations
                state = .ready(p)
            }
        }
    }

    public func updateProjectSettings(description: String, githubRepo: String?, for project: Project) {
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

    /// Persists the full build-metadata block (identity, versioning, signing,
    /// deployment, Swift version, configuration overrides, Xcode setting overrides).
    public func updateProjectBuildMetadata(_ metadata: ProjectBuildSettings, for project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx].buildSettings = metadata
            saveMetadata(projects[idx])
        }
        if activeProject?.id == project.id {
            if case .ready(var p) = state {
                p.buildSettings = metadata
                state = .ready(p)
            }
        }
    }

    /// Renames the project metadata without moving anything on disk. Only safe
    /// for projects whose directory does not derive from the name
    /// (customDirectoryPath projects). Default-root projects must use
    /// renameProject(_:to:) so the folder moves with the name.
    public func updateProjectName(_ name: String, for project: Project) {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return }
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

    // MARK: - Session Actions

    private var openingTask: Task<Void, Never>?

    public func openProject(_ project: Project) async {
        openingTask?.cancel()
        openingTask = Task {
            guard !Task.isCancelled else { return }

            state = .resolving
            logger.info("Opening project: \(project.name)")

            do {
                let loadedProject = try await coordinator.loadProjectWithTimeout(url: project.directoryURL)
                if Task.isCancelled { return }

                // Get or create independent session
                let session = self.getOrCreateSession(for: loadedProject)
                self.activeSession = session

                state = .ready(loadedProject)

                // Opening a project (not just creating one) creates
                // its SwiftCode/ metadata directory with
                // swiftcode.json, session.json, and project.json
                // derived from this project. Best-effort: a failure
                // here must never fail the open itself, and existing
                // files are never overwritten — only missing ones
                // are created, and the project.json copy is refreshed.
                self.ensureSwiftCodeMetadataOnOpen(for: loadedProject, session: session)

                // Reset and isolate DocumentCoordinator state to prevent Project A vs B loading bug
                DocumentCoordinator.shared.projectURL = loadedProject.directoryURL
                DocumentCoordinator.shared.activeDocument = nil
                DocumentCoordinator.shared.visualUIDocument = nil
                DocumentCoordinator.shared.compiledArtboardViews = [:]
                DocumentCoordinator.shared.compiledArtboardErrors = [:]
                DocumentCoordinator.shared.previewSession = nil
                DocumentCoordinator.shared.inspectorSelection = nil

                // Auto-discover and decode .xcstrings localization files immediately on project open
                LocalizationCore.shared.scanProjectFiles(projectURL: loadedProject.directoryURL)

                // Update last opened date in library
                if let idx = self.projects.firstIndex(where: { $0.id == project.id }) {
                    var updated = self.projects[idx]
                    updated.lastOpened = Date()
                    self.projects[idx] = updated
                    self.saveMetadata(updated)
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

    public func closeProject() {
        openingTask?.cancel()
        if let currentSession = activeSession {
            saveSession(currentSession)
        }
        state = .idle
        activeSession = nil

        // Completely reset DocumentCoordinator
        DocumentCoordinator.shared.projectURL = nil
        DocumentCoordinator.shared.activeDocument = nil
        DocumentCoordinator.shared.visualUIDocument = nil
        DocumentCoordinator.shared.compiledArtboardViews = [:]
        DocumentCoordinator.shared.compiledArtboardErrors = [:]
        DocumentCoordinator.shared.previewSession = nil
        DocumentCoordinator.shared.inspectorSelection = nil
    }

    public func retryLoad(for project: Project) async {
        state = .idle
        await openProject(project)
    }

    public func cancelLoad() {
        openingTask?.cancel()
        state = .cancelled
    }

    // MARK: - CRUD Operations

    public func createProject(name: String) throws -> Project {
        let sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { throw ProjectOpenError.pathNotFound } // Reusing or should define specific CRUD errors

        let projectDir = projectsDirectory.appendingPathComponent(sanitized)
        guard !fm.fileExists(atPath: projectDir.path) else {
            throw ProjectOpenError.underlyingIO(NSError(domain: "SwiftCode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project already exists"]))
        }

        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // New projects get a SwiftCode/ metadata directory. It holds
        // swiftcode.json (the manifest) and a project.json copy; the
        // root project.json written below stays the open-time source
        // of truth, and the copy is refreshed on every later save
        // (see refreshSwiftCodeProjectJSONCopy).
        try fm.createDirectory(at: projectDir.appendingPathComponent("SwiftCode"), withIntermediateDirectories: true)

        var project = Project(name: sanitized)
        project.description = "A new SwiftCode project"
#if canImport(SwiftCodeCollaboration)
        project.transferConfiguration = .owner
#endif

        // Apply default organization prefix to the bundle identifier
        let prefix = AppSettings.shared.defaultOrganization
        let suffix = prefix.hasSuffix(".") ? "" : "."
        let bundleID = "\(prefix)\(suffix)\(sanitized.lowercased().replacingOccurrences(of: " ", with: "-"))"
        project.ciBuildConfiguration = CIBuildConfiguration(
            platform: .iOS,
            deploymentTarget: "16.0",
            targetDeviceFamily: .iPhoneAndIPad,
            schemeName: sanitized,
            bundleIdentifier: bundleID
        )

        // saveMetadataInPlace (not the root-only saveMetadata) so
        // the fresh project also gets its SwiftCode/swiftcode.json
        // manifest and its SwiftCode/project.json copy immediately.
        try saveMetadataInPlace(project)
        projects.insert(project, at: 0)
        return project
    }

    public func deleteProject(_ project: Project) throws {
        try fm.removeItem(at: project.directoryURL)
        projects.removeAll { $0.id == project.id }
        if activeProject?.id == project.id {
            closeProject()
        }
    }

    public func removeProjectFromRecents(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        if activeProject?.id == project.id {
            closeProject()
        }
    }

    public func renameProject(_ project: Project, to newName: String) throws {
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

    public func duplicateProject(_ project: Project) throws -> Project {
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
#if canImport(SwiftCodeCollaboration)
        newProject.transferConfiguration = project.transferConfiguration
#endif
        try saveMetadata(newProject)

        projects.insert(newProject, at: 0)
        return newProject
    }

    public func ensureSwiftCodeJSON(for project: Project, at directoryURL: URL) {
        // When the project has a SwiftCode/ metadata directory, the
        // manifest lives there — not at the project root. Opening a
        // project creates that directory (see
        // ensureSwiftCodeMetadataOnOpen), so pre-SwiftCode/ projects
        // gain it on first open; a root manifest is copied in first
        // rather than discarded, and is never deleted.
        let swiftCodeDir = directoryURL.appendingPathComponent("SwiftCode")
        var isDir: ObjCBool = false
        let manifestDir = (fm.fileExists(atPath: swiftCodeDir.path, isDirectory: &isDir) && isDir.boolValue)
            ? swiftCodeDir : directoryURL
        let manifestURL = manifestDir.appendingPathComponent("swiftcode.json")

        if fm.fileExists(atPath: manifestURL.path) {
            if let data = try? Data(contentsOf: manifestURL),
               var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                json["name"] = project.name
                if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                    try? updatedData.write(to: manifestURL, options: .atomic)
                }
            }
            return
        }

        let rawSlug = project.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let sanitizedID = "com.swiftcode.project.\(rawSlug)"
        // Written with the private nested manifest structs at the foot
        // of this file (Legacy's `SDKManifest` shape, same encoder
        // settings), so the bytes are unchanged by the port.
        let manifest = SwiftCodeManifestJSON(
            manifestVersion: 1,
            id: sanitizedID,
            name: project.name,
            version: "0.1.0",
            description: project.description,
            type: "app",
            runtime: SwiftCodeManifestRuntimeJSON(language: "typescript", entrypoint: "dist/index.js", minimumSwiftCodeVersion: "1.0.0"),
            sdk: SwiftCodeManifestSDKRefJSON(name: "@swiftcode/sdk", versionRange: "^1.0.0", protocolVersion: 1),
            capabilities: [],
            assist: SwiftCodeManifestAssistJSON(requested: false)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    /// Creates (or completes) the project's SwiftCode/ metadata
    /// directory on open. Contents, all derived from the opened
    /// project — never invented from another project:
    /// - `SwiftCode/project.json`: a copy of the root project.json
    ///   (the root file stays the open-time source of truth).
    /// - `SwiftCode/swiftcode.json`: the root manifest copied in
    ///   when one exists and the copy does not, otherwise created
    ///   by ensureSwiftCodeJSON (which also refreshes its name).
    /// - `SwiftCode/session.json`: a copy of the active session.
    /// Existing files are never overwritten, except the
    /// project.json copy, which is refreshed like every save.
    public func ensureSwiftCodeMetadataOnOpen(for project: Project, session: ProjectSession) {
        let swiftCodeDir = project.directoryURL.appendingPathComponent("SwiftCode")
        try? fm.createDirectory(at: swiftCodeDir, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: swiftCodeDir.path, isDirectory: &isDir), isDir.boolValue else { return }
        let manifestCopy = swiftCodeDir.appendingPathComponent("swiftcode.json")
        if !fm.fileExists(atPath: manifestCopy.path) {
            let rootManifest = project.directoryURL.appendingPathComponent("swiftcode.json")
            if fm.fileExists(atPath: rootManifest.path) {
                try? fm.copyItem(at: rootManifest, to: manifestCopy)
            }
        }
        do {
            let projectEncoder = JSONEncoder()
            projectEncoder.dateEncodingStrategy = .iso8601
            let projectData = try projectEncoder.encode(project)
            // Root project.json is written by saveMetadata, not here;
            // only the SwiftCode/ copy is refreshed on open.
            refreshSwiftCodeProjectJSONCopy(for: project, data: projectData)
        } catch {
            // Best-effort: a failed copy never fails the open.
        }
        ensureSwiftCodeJSON(for: project, at: project.directoryURL)
        if let sessionData = try? JSONEncoder().encode(session) {
            try? sessionData.write(to: swiftCodeDir.appendingPathComponent("session.json"), options: .atomic)
        }
    }

    /// Keeps the SwiftCode/project.json copy in sync when the project
    /// has a SwiftCode/ directory. Best-effort by design: the root
    /// project.json is the source of truth, and a failed copy must
    /// never fail a save.
    private func refreshSwiftCodeProjectJSONCopy(for project: Project, data: Data) {
        let dir = project.directoryURL.appendingPathComponent("SwiftCode")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { return }
        try? data.write(to: dir.appendingPathComponent("project.json"), options: .atomic)
    }

    public func saveMetadataInPlace(_ project: Project) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let metaURL = project.directoryURL.appendingPathComponent("project.json")
        try data.write(to: metaURL, options: .atomic)
        refreshSwiftCodeProjectJSONCopy(for: project, data: data)
        ensureSwiftCodeJSON(for: project, at: project.directoryURL)
    }

    public func importProject(from url: URL, name customName: String? = nil) async throws -> Project {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        // Determine project root directory
        var rootURL = url
        if url.pathExtension == "xcodeproj" || url.pathExtension == "xcworkspace" {
            rootURL = url.deletingLastPathComponent()
        }

        let pathStr = rootURL.path

        // 1. Prevent duplicates: check if directory is already imported
        if let existing = projects.first(where: {
            let existingPath = $0.customDirectoryPath ?? (CodingManager.shared.projectsRoot.appendingPathComponent($0.name).path)
            return existingPath == pathStr
        }) {
            return existing
        }

        // 2. Automatically determine and extract all metadata
        let name = customName ?? rootURL.lastPathComponent

        // Scan schemes. Legacy read the schemes of the active project
        // through `XcodeBuildAPI.shared.discoverActiveProject()`; that
        // type has no definition anywhere (not in Legacy, not on main),
        // so there is nothing to port. The destination equivalent is
        // the imported root's own schemes: the `.xcscheme` files inside
        // any `.xcodeproj` / `.xcworkspace` bundle at the root
        // (`Scheme.discover(in:)`, SwiftCodeWorkspace). With none,
        // Legacy's `?? [name]` fallback applies.
        let fmContents = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        let schemes: [String] = {
            let containers = (fmContents ?? []).filter { $0.pathExtension == "xcodeproj" || $0.pathExtension == "xcworkspace" }
            let found = containers.flatMap { Scheme.discover(in: $0).map(\.name) }
            return found.isEmpty ? [name] : found
        }()

        // Try parsing bundle ID using the destination's own pbxproj
        // parser (`PBXProj`, SwiftCodeProject) — Legacy's
        // `XcodeProjParse` (552 lines, its own PBX model) is superseded
        // by it. Target names come from the project's target list; the
        // bundle identifier is the first PRODUCT_BUNDLE_IDENTIFIER
        // across the XCBuildConfiguration objects, the same lookup
        // Legacy did (`DestinationMenu.swift` uses the identical
        // access shape).
        var bundleID = "com.example.\(name.lowercased())"
        var targetsList: [String] = []
        if let xcodeproj = fmContents?.first(where: { $0.pathExtension == "xcodeproj" }) {
            if let parsed = try? PBXProj(contentsOf: xcodeproj) {
                targetsList = parsed.targets.compactMap { $0.string("name") }
                // `targetsList` is assigned and never read below, exactly
                // as in Legacy — kept for fidelity.
                for config in parsed.objects(isa: "XCBuildConfiguration") {
                    if let bid = config["buildSettings"]?.dictionary?["PRODUCT_BUNDLE_IDENTIFIER"]?.string {
                        bundleID = bid
                        break
                    }
                }
            }
        }

        // Create CI build configuration
        let ciConfig = CIBuildConfiguration(
            platform: .iOS,
            deploymentTarget: "16.0",
            targetDeviceFamily: .iPhoneAndIPad,
            schemeName: schemes.first ?? name,
            bundleIdentifier: bundleID
        )

        var project = Project(name: name)
        project.customDirectoryPath = pathStr
        project.description = "Imported Xcode Project"
        project.ciBuildConfiguration = ciConfig
#if canImport(SwiftCodeCollaboration)
        project.transferConfiguration = .owner
#endif

        // Scan files at initial level
        project.files = try await coordinator.buildFileTreeInternal(at: rootURL, relativeTo: rootURL)

        // Save metadata file in-place inside the project folder
        try saveMetadataInPlace(project)

        // Add to active library list and persist
        projects.insert(project, at: 0)

        // Create its own independent session
        _ = getOrCreateSession(for: project)

        return project
    }

    // MARK: - Finder-opened .scproj packages

    // Trust granted from the Finder-open trust alert lives in
    // `SwiftCodeIDEShell.ScprojTrustStore` (identical API to Legacy's
    // nested enum) — not redefined here. A
    // trusted package path opens without prompting again; trust is per
    // directory path, is only ever granted from that alert, and is
    // forgotten when the package is deleted through the same alert.

    /// Opens a `.scproj` package directory from Finder, after the
    /// trust alert in SwiftCodeApp has approved it. A package is a
    /// directory holding `project.json` (at its root, or inside
    /// `SwiftCode/` for the new layout). Unlike `importProject`,
    /// this never mints a new project id or overwrites the package's
    /// own metadata with an imported copy: the package's project is
    /// the project that opens.
    public func openScprojPackage(at url: URL) async throws -> Project {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectOpenError.pathNotFound
        }
        if let existing = projects.first(where: {
            $0.directoryURL.standardizedFileURL.path == url.standardizedFileURL.path
        }) {
            return existing
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let candidates = [
            url.appendingPathComponent("project.json"),
            url.appendingPathComponent("SwiftCode/project.json"),
        ]
        var decoded: Project?
        for metaURL in candidates {
            if let data = try? Data(contentsOf: metaURL),
               let project = try? decoder.decode(Project.self, from: data) {
                decoded = project
                break
            }
        }

        var resolved: Project
        if var project = decoded {
            // Point the decoded project at the package wherever it
            // lives on disk; without this, directoryURL would resolve
            // through the projects root and miss the package.
            project.customDirectoryPath = url.path
            project.lastOpened = Date()
            resolved = project
        } else {
            var fresh = Project(name: url.deletingPathExtension().lastPathComponent)
            fresh.customDirectoryPath = url.path
            fresh.description = "SwiftCode project package"
            resolved = fresh
            try saveMetadataInPlace(resolved)
        }

        projects.insert(resolved, at: 0)
        _ = getOrCreateSession(for: resolved)
        return resolved
    }

    private func loadOrCreateProject(at url: URL) throws -> Project {
        let metaURL = url.appendingPathComponent("project.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: metaURL),
           let project = try? decoder.decode(Project.self, from: data) {
            return project
        } else {
            let name = url.lastPathComponent
            var project = Project(name: name)

            // Apply default organization prefix to the bundle identifier
            let prefix = AppSettings.shared.defaultOrganization
            let suffix = prefix.hasSuffix(".") ? "" : "."
            let bundleID = "\(prefix)\(suffix)\(name.lowercased().replacingOccurrences(of: " ", with: "-"))"
            project.ciBuildConfiguration = CIBuildConfiguration(
                platform: .iOS,
                deploymentTarget: "16.0",
                targetDeviceFamily: .iPhoneAndIPad,
                schemeName: name,
                bundleIdentifier: bundleID
            )

            try saveMetadataInPlace(project)
            return project
        }
    }

    // MARK: - File Operations

    private var currentFileLoadTask: Task<Void, Never>?

    public func openFile(_ node: FileNode) {
        guard !node.isDirectory else { return }
        guard let project = activeProject else { return }

        currentFileLoadTask?.cancel()
        fileLoadError = nil
        activeFileNode = node

        if !openFileTabs.contains(where: { $0.id == node.id }) {
            openFileTabs.append(node)
        }

        if let currentSession = activeSession {
            saveSession(currentSession)
        }

        let projectName = project.name
        let relativePath = node.path
        let nodeId = node.id

        currentFileLoadTask = Task {
            do {
                let fileURL = project.directoryURL.appendingPathComponent(relativePath)
                let content = try await self.readFileContent(at: fileURL)
                guard !Task.isCancelled, self.activeFileNode?.id == nodeId else { return }
                self.activeFileContent = content
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
                guard !Task.isCancelled, self.activeFileNode?.id == nodeId else { return }
                self.activeFileContent = ""
                self.fileLoadError = "Failed to load: \(error.localizedDescription)"
            }
        }
    }

    public func openFile(atPath relativeOrAbsolutePath: String) {
        guard let project = activeProject else { return }

        let projectPath = project.directoryURL.standardizedFileURL.path
        var relativePath = relativeOrAbsolutePath
        if relativePath.hasPrefix(projectPath) {
            relativePath = String(relativePath.dropFirst(projectPath.count))
        }
        while relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }

        let fileURL = project.directoryURL.appendingPathComponent(relativePath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        let fileName = fileURL.lastPathComponent
        let node = FileNode(name: fileName, path: relativePath, isDirectory: false)
        openFile(node)
        refreshFileTree(for: project)
    }

    public func recordAssistFileMutation(
        path: String,
        beforeContent: String,
        afterContent: String,
        addedLines: Int,
        deletedLines: Int
    ) {
        let diff = AssistSessionFileDiff(
            filePath: path,
            beforeContent: beforeContent,
            afterContent: afterContent,
            addedLines: addedLines,
            deletedLines: deletedLines
        )
        self.activeFileDiff = diff
        self.showDiffBanner = (addedLines > 0 || deletedLines > 0)
        self.openFile(atPath: path)
    }

    public func dismissDiffBanner() {
        self.showDiffBanner = false
        self.activeFileDiff = nil
    }

    private func readFileContent(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else {
                throw NSError(domain: "SwiftCode.FileRead", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a regular file"])
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            if let text = Self.decodeText(from: data) {
                return text
            } else {
                let sizeDesc = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                return "Binary file (\(sizeDesc)) — not previewable."
            }
        }.value
    }

    // Static (was an instance method in Legacy) so `readFileContent`'s
    // detached task does not capture the MainActor-isolated store; the
    // function is pure, so this changes no behaviour.
    private static func decodeText(from data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16LittleEndian) { return s }
        if let s = String(data: data, encoding: .utf16BigEndian) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        if let s = String(data: data, encoding: .ascii) { return s }
        return nil
    }

    public func closeTab(_ node: FileNode) {
        openFileTabs.removeAll { $0.id == node.id }
        if activeFileNode?.id == node.id {
            if let last = openFileTabs.last {
                openFile(last)
            } else {
                activeFileNode = nil
                activeFileContent = ""
            }
        }
        if let currentSession = activeSession {
            saveSession(currentSession)
        }
    }

    public func saveCurrentFile(content: String) {
        guard let project = activeProject, let node = activeFileNode else { return }
        do {
            try CodingManager.shared.writeFile(content: content, at: node.path, in: project.directoryURL)
            activeFileContent = content
            modifiedFilePaths.remove(node.path)
            fileLoadError = nil
            if let currentSession = activeSession {
                saveSession(currentSession)
            }
        } catch {
            fileLoadError = "Failed to save: \(error.localizedDescription)"
        }
    }

    public func saveAll() {
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

    public func markFileModified(path: String) {
        modifiedFilePaths.insert(path)
    }

    public func createFile(named name: String, inDirectory directoryPath: String?, project: Project, initialContent: String? = nil) throws {
        let content = initialContent ?? (name.hasSuffix(".swift") ? generateSwiftTemplate(for: name, in: project) : "")
        try CodingManager.shared.createFile(named: name, at: directoryPath, in: project.directoryURL, content: content)
        refreshFileTree(for: project)
    }

    public func createFolder(named name: String, inDirectory directoryPath: String?, project: Project) throws {
        try CodingManager.shared.createDirectory(named: name, at: directoryPath, in: project.directoryURL)
        refreshFileTree(for: project)
    }

    public func deleteNode(_ node: FileNode, project: Project) throws {
        try CodingManager.shared.deleteItem(at: node.path, in: project.directoryURL)
        if activeFileNode?.id == node.id {
            activeFileNode = nil
            activeFileContent = ""
        }
        refreshFileTree(for: project)
    }

    public func renameNode(_ node: FileNode, to newName: String, project: Project) throws {
        try CodingManager.shared.renameItem(at: node.path, to: newName, in: project.directoryURL)
        refreshFileTree(for: project)
    }

    public func updateCIBuildConfiguration(_ configuration: CIBuildConfiguration, for project: Project) {
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

    public func refreshFileTree(for project: Project) {
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

    public func rebuildFileTree(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let basePath = url.standardizedFileURL.path

        let metadataFiles = [
            "manifest.json", "metadata.json", "integrity.json",
            "version.json", "project.json", "project.xml", "project.plist"
        ]

        let deferredDirectoryNames: Set<String> = [
            ".build", ".git", "DerivedData", "node_modules", "Pods", "build"
        ]

        var nodes: [FileNode] = []

        for childURL in contents {
            let filename = childURL.lastPathComponent
            if metadataFiles.contains(filename) { continue }

            let resourceValues = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            let isDir = resourceValues?.isDirectory ?? false
            if resourceValues?.isSymbolicLink == true || (isDir && deferredDirectoryNames.contains(filename)) {
                continue
            }

            let childPath = childURL.standardizedFileURL.path
            let relativePath = childPath.hasPrefix(basePath + "/")
                ? String(childPath.dropFirst(basePath.count + 1))
                : filename

            nodes.append(FileNode(name: filename, path: relativePath, isDirectory: isDir))
        }

        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func saveImportedProject(_ project: Project) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let metaURL = project.directoryURL.appendingPathComponent("project.json")
        try data.write(to: metaURL, options: .atomic)
        refreshSwiftCodeProjectJSONCopy(for: project, data: data)

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
            refreshSwiftCodeProjectJSONCopy(for: project, data: data)
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

    // MARK: - swiftcode.json writer

    // Private mirror of Legacy's `SDKManifest` shape
    // (`SwiftCode/SDK/Contracts/Manifest/SDKManifest.swift`), used only
    // by `ensureSwiftCodeJSON`. The manifest type already on main
    // (`SwiftCodeManifest` in SwiftCodeExtensions) is the renamed SDK
    // Studio model, which this target does not depend on; these nested
    // structs keep the store's writer self-contained while emitting
    // byte-identical JSON for this input (same fields, same values,
    // same `JSONEncoder` settings as Legacy: `.prettyPrinted,
    // .sortedKeys`, no `.withoutEscapingSlashes`). `contributes` is
    // nil and `unknownFields` is empty in Legacy's construction, so
    // neither key is emitted — exactly as Legacy's custom `encode`
    // did (`encodeIfPresent` / empty-dict skip).

    private struct SwiftCodeManifestJSON: Codable {
        var manifestVersion: Int
        var id: String
        var name: String
        var version: String
        var description: String?
        var type: String
        var runtime: SwiftCodeManifestRuntimeJSON
        var sdk: SwiftCodeManifestSDKRefJSON
        var capabilities: [SwiftCodeManifestCapabilityJSON]
        var assist: SwiftCodeManifestAssistJSON
    }

    private struct SwiftCodeManifestRuntimeJSON: Codable {
        var language: String
        var entrypoint: String
        var minimumSwiftCodeVersion: String
    }

    private struct SwiftCodeManifestSDKRefJSON: Codable {
        var name: String
        var versionRange: String
        var protocolVersion: Int
    }

    private struct SwiftCodeManifestCapabilityJSON: Codable {
        var id: String
        var reason: String
    }

    private struct SwiftCodeManifestAssistJSON: Codable {
        var requested: Bool
    }
}
