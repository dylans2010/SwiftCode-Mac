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
            let totalStartTime = CFAbsoluteTimeGetCurrent()
            logger.info("[BEGIN] Workspace Created - Init loading task | Thread: \(Thread.isMainThread ? "Main" : "Background") | Actor: WorkspaceViewModel")

            let gitInstStart = CFAbsoluteTimeGetCurrent()
            await git.refreshInstallationStatus()
            logger.info("Git Initialized - refreshInstallationStatus elapsed: \(CFAbsoluteTimeGetCurrent() - gitInstStart, format: .fixed(precision: 4))s")
            if Task.isCancelled { return }

            let treeStart = CFAbsoluteTimeGetCurrent()
            logger.info("[BEGIN] File Tree Generated")
            await projectTree.loadProject(url: projectURL)
            logger.info("[END] File Tree Generated - elapsed: \(CFAbsoluteTimeGetCurrent() - treeStart, format: .fixed(precision: 4))s")
            if Task.isCancelled { return }

            let gitStatusStart = CFAbsoluteTimeGetCurrent()
            await git.refreshStatus()
            logger.info("Git Status Refreshed - elapsed: \(CFAbsoluteTimeGetCurrent() - gitStatusStart, format: .fixed(precision: 4))s")

            let xcodeScanStart = CFAbsoluteTimeGetCurrent()
            logger.info("[BEGIN] Package Resolution Started")
            await scanAndCacheXcodeProjects()
            logger.info("[END] Package Resolution Finished - elapsed: \(CFAbsoluteTimeGetCurrent() - xcodeScanStart, format: .fixed(precision: 4))s")

            let totalElapsed = CFAbsoluteTimeGetCurrent() - totalStartTime
            logger.info("[END] Workspace Ready - All subsystems initialized | Total Elapsed: \(totalElapsed, format: .fixed(precision: 4))s")
            if totalElapsed > 5.0 {
                logger.warning("[PERFORMANCE WARNING] Workspace subsystems initialization took \(totalElapsed, format: .fixed(precision: 4))s which is over acceptable threshold of 5s.")
            }
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
        let projectURL = self.projectURL

        let result = await Task.detached(priority: .userInitiated) { () -> [URL: XcodeProjModel] in
            let fm = FileManager.default
            let deferredDirectoryNames: Set<String> = [
                ".build", ".git", "DerivedData", "node_modules", "Pods", "build"
            ]

            guard let enumerator = fm.enumerator(
                at: projectURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return [:] }

            var xcodeProjURLs: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                let lastComponent = fileURL.lastPathComponent
                if deferredDirectoryNames.contains(lastComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                if fileURL.pathExtension == "xcodeproj" {
                    xcodeProjURLs.append(fileURL)
                    enumerator.skipDescendants()
                }
            }

            var cached: [URL: XcodeProjModel] = [:]
            for url in xcodeProjURLs {
                do {
                    let model = try XcodeProjParse.shared.parse(projectURL: url)
                    cached[url] = model
                    cached[url.appendingPathComponent("project.pbxproj")] = model
                } catch {
                    // Fail gracefully in background thread
                }
            }
            return cached
        }.value

        self.parsedXcodeProjects = result
        ProjectResolutionService.shared.updateParsedProjects(with: result)
        logger.info("Successfully scanned and cached \(result.count / 2) xcodeproj(s).")
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
