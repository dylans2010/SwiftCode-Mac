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

    // Centralized Navigation State
    public var activeSheet: ToolbarActionManager.SheetDestination? = nil {
        didSet {
            logger.info("Centralized Navigation activeSheet changed to: \(self.activeSheet?.rawValue ?? "None", privacy: .public)")
        }
    }
    public var showingExportSheet = false

    // Docked AI Agent Inspector state
    public var isAgentChatVisible = false {
        didSet {
            UserDefaults.standard.set(isAgentChatVisible, forKey: "com.swiftcode.agentChatVisible")
        }
    }
    public var agentChatWidth: Double = 320.0 {
        didSet {
            if agentChatWidth > 150 {
                UserDefaults.standard.set(agentChatWidth, forKey: "com.swiftcode.agentChatWidth")
            }
        }
    }

    @ObservationIgnored nonisolated(unsafe) private var loadingTask: Task<Void, Never>?
    @ObservationIgnored private var lastSelectedFileID: String?

    public init(projectURL: URL) {
        self.projectURL = projectURL
        self.git.repositoryURL = projectURL

        // Restore agent chat inspector state
        self.isAgentChatVisible = UserDefaults.standard.bool(forKey: "com.swiftcode.agentChatVisible")
        let savedWidth = UserDefaults.standard.double(forKey: "com.swiftcode.agentChatWidth")
        self.agentChatWidth = savedWidth > 150 ? savedWidth : 320.0

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
        ProjectResolutionService.shared.updateParsedProjects(with: parsedXcodeProjects)
    }

    public func handleFileSelectionChange(nodeID: String?) {
        guard let nodeID = nodeID, nodeID != lastSelectedFileID else { return }
        lastSelectedFileID = nodeID

        let url = URL(fileURLWithPath: nodeID)

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
