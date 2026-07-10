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
        }
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
