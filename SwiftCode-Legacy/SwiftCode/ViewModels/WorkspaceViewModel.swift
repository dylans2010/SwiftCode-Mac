import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkspaceViewModel")

@Observable
@MainActor
public class WorkspaceViewModel: Sendable {
    public let projectURL: URL
    public let editor = EditorViewModel()
    public let projectTree = ProjectTreeViewModel()
    public let git = GitViewModel()
    public let build = BuildViewModel()
    public let debug = DebugSessionViewModel()
    public let ai = AgentViewModel()
    private let sessionStore = ProjectSessionStore.shared

    public var parsedXcodeProjects: [URL: XcodeProjModel] = [:]

    @ObservationIgnored nonisolated(unsafe) private var loadingTask: Task<Void, Never>?

    public init(projectURL: URL) {
        self.projectURL = projectURL
        self.git.repositoryURL = projectURL
        self.loadingTask = Task {
            await git.refreshInstallationStatus()
            if Task.isCancelled { return }
            await projectTree.loadProject(url: projectURL)
            if Task.isCancelled { return }
            await git.refreshStatus()
            await scanAndCacheXcodeProjects()

            // Auto open the active file from session, and restore all open tabs from the session
            let sessionStore = ProjectSessionStore.shared
            if let session = sessionStore.activeSession {
                // Restore navigation expanded nodes
                projectTree.expandedNodeIDs = session.expandedNodeIDs
                projectTree.selectedNodeID = session.selectedNodeID

                // Restore open tabs
                for node in session.openFileTabs {
                    let tabURL = projectURL.appendingPathComponent(node.path)
                    if tabURL != projectURL.appendingPathComponent(session.activeFileNode?.path ?? "") {
                        await editor.openFile(url: tabURL)
                    }
                }

                // Then open the active file (which will select it)
                if let activeNode = session.activeFileNode {
                    let fileURL = projectURL.appendingPathComponent(activeNode.path)
                    await editor.openFile(url: fileURL)
                }
            } else if let rootNode = projectTree.rootNode, let children = rootNode.children {
                if let primaryURL = findPrimarySwiftFile(in: children) {
                    let relativePath = primaryURL.path.replacingOccurrences(of: projectURL.path + "/", with: "")
                    let node = FileNode(name: primaryURL.lastPathComponent, path: relativePath, isDirectory: false)
                    sessionStore.openFile(node)
                    await editor.openFile(url: primaryURL)
                }
            }
        }
    }

    private func findPrimarySwiftFile(in nodes: [ProjectNode]) -> URL? {
        // First look for important files in the current level
        for node in nodes {
            if node.kind == .file {
                let name = node.url.lastPathComponent
                if name == "ContentView.swift" || name == "main.swift" || name == "Package.swift" {
                    return node.url
                }
            }
        }

        // Then search recursively for any .swift file
        for node in nodes {
            if node.kind == .file && node.url.pathExtension == "swift" {
                return node.url
            }
            if let children = node.children {
                if let childMatch = findPrimarySwiftFile(in: children) {
                    return childMatch
                }
            }
        }

        // Fallback to any file
        for node in nodes {
            if node.kind == .file {
                return node.url
            }
            if let children = node.children {
                if let childMatch = findAnyFile(in: children) {
                    return childMatch
                }
            }
        }
        return nil
    }

    private func findAnyFile(in nodes: [ProjectNode]) -> URL? {
        for node in nodes {
            if node.kind == .file {
                return node.url
            }
            if let children = node.children {
                if let childMatch = findAnyFile(in: children) {
                    return childMatch
                }
            }
        }
        return nil
    }

    deinit {
        let task = loadingTask
        Task.detached {
            task?.cancel()
        }
    }

    public func scanAndCacheXcodeProjects() async {
        logger.info("Scanning for xcodeproj in workspace: \(self.projectURL.path, privacy: .public)")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: projectURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }

        var xcodeProjURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathExtension == "xcodeproj" {
                xcodeProjURLs.append(fileURL)
            }
        }

        for url in xcodeProjURLs {
            do {
                let model = try XcodeProjParse.shared.parse(projectURL: url)
                parsedXcodeProjects[url] = model
                parsedXcodeProjects[url.appendingPathComponent("project.pbxproj")] = model
                logger.info("Successfully scanned and cached: \(url.lastPathComponent, privacy: .public)")
            } catch {
                logger.error("Failed to parse scanned xcodeproj at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        ProjectResolutionService.shared.updateParsedProjects(with: parsedXcodeProjects)
    }

    public func handleFileSelectionChange(nodeID: String?) {
        guard let nodeID = nodeID else { return }
        // The ID is the full path of the file
        let url = URL(fileURLWithPath: nodeID)

        // Ensure it's not a directory (IDs for folders also come through here)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: nodeID, isDirectory: &isDir), isDir.boolValue {
            if url.pathExtension != "xcodeproj" {
                return
            }
        }

        Task {
            if let project = sessionStore.activeProject,
               let node = project.files.first(where: { url.path.hasSuffix($0.path) }) {
                sessionStore.openFile(node)
            }
            await editor.openFile(url: url)
        }
    }
}
