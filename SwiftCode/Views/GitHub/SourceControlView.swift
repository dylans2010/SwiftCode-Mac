import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "SourceControlView")

// MARK: - Native Source Control Window Manager
@MainActor
public final class SourceControlWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SourceControlWindowManager()
    private var windowController: SourceControlWindowController?

    public func showWindow(for project: Project, gitViewModel: GitViewModel) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = SourceControlWindowController(gitViewModel: gitViewModel, project: project)
        wc.window?.delegate = self
        self.windowController = wc
        wc.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

// MARK: - Native Source Control Window Controller
@MainActor
public class SourceControlWindowController: NSWindowController {
    public let gitViewModel: GitViewModel
    public let project: Project

    public init(gitViewModel: GitViewModel, project: Project) {
        self.gitViewModel = gitViewModel
        self.project = project

        let window = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Source Control Workspace"
        window.minSize = NSSize(width: 1000, height: 700)
        window.setFrameAutosaveName("SourceControlMainWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)

        let splitVC = SourceControlSplitViewController(gitViewModel: gitViewModel, project: project)
        window.contentViewController = splitVC

        setupToolbar(window: window)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "SourceControlToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }
}

extension SourceControlWindowController: NSToolbarDelegate {
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleSidebar:
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Toggle Git Categories Sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleSidebarAction(_:))
            return item

        default:
            return nil
        }
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .space]
    }
}

extension SourceControlWindowController {
    @objc private func toggleSidebarAction(_ sender: Any?) {
        if let splitVC = contentViewController as? SourceControlSplitViewController {
            splitVC.toggleSidebar(sender)
        }
    }
}

// ====================================================================
// NAVIGATION SELECTIONS
// ====================================================================
public enum SourceControlSelection: String, CaseIterable, Identifiable, Codable {
    case localWorkspace = "Local Workspace"
    case gitWorktrees = "Git Worktrees"
    case changes = "Changes"
    case branches = "Branches"
    case commitHistory = "Commit History"
    case pullRequests = "Pull Requests"
    case github = "GitHub"
    case actions = "Actions"
    case activityFeed = "Activity Feed"
    case discussions = "Discussions"
    case githubAccount = "GitHub Account"
    case githubCodeSearch = "GitHub Code Search"
    case notifications = "Notifications"
    case releases = "Releases"
    case tags = "Tags"
    case issues = "Issues"
    case gitBlame = "Git Blame"
    case repositoryExplorer = "Repository Explorer"
    case repositoryAutomationBuilder = "Repository Automation Builder"
    case swiftCodeWorkflows = "SwiftCode Workflows"
    case diffViewer = "Diff Viewer"
    case cli = "CLI"
    case repositorySettings = "Repository Settings"
    case onboarding = "Onboarding"
    case repositoryIntelligence = "Repository Intelligence"
    case knowledgeGraph = "Repository Knowledge Graph"
    case repositoryTimeline = "Repository Timeline"
    case gitOperations = "Git Operations Center"
    case advancedDiff = "Advanced Diff Center"
    case repositorySearch = "Repository Search Platform"
    case codeOwnership = "Code Ownership Workspace"
    case branchIntelligence = "Branch Intelligence"
    case commitIntelligence = "Commit Intelligence"
    case pullRequestIntelligence = "Pull Request Intelligence"
    case securityCenter = "Security Center"
    case collaborationCenter = "Collaboration Center"
    case workspaceAutomation = "Workspace Automation"
    case githubDiscovery = "GitHub Discovery"
    case aiAssistant = "AI Repository Assistant"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .repositoryIntelligence: return "chart.bar.doc.horizontal"
        case .knowledgeGraph: return "circle.grid.3x3"
        case .repositoryTimeline: return "calendar.day.timeline.left"
        case .gitOperations: return "command"
        case .advancedDiff: return "doc.text.magnifyingglass"
        case .repositorySearch: return "magnifyingglass.circle"
        case .codeOwnership: return "person.3.sequence"
        case .branchIntelligence: return "arrow.triangle.branch"
        case .commitIntelligence: return "clock"
        case .pullRequestIntelligence: return "arrow.triangle.pull"
        case .securityCenter: return "shield.righthalf.filled"
        case .collaborationCenter: return "person.2"
        case .workspaceAutomation: return "cpu"
        case .githubDiscovery: return "safari"
        case .aiAssistant: return "sparkles"
        case .gitWorktrees: return "arrow.triangle.branch"
        case .localWorkspace: return "laptopcomputer"
        case .changes: return "doc.badge.plus"
        case .branches: return "arrow.triangle.branch"
        case .commitHistory: return "clock.arrow.circlepath"
        case .pullRequests: return "arrow.triangle.pull"
        case .github: return "square.grid.2x2.fill"
        case .actions: return "play.circle.fill"
        case .activityFeed: return "bolt.fill"
        case .discussions: return "bubble.left.and.bubble.right.fill"
        case .githubAccount: return "person.crop.circle.fill"
        case .githubCodeSearch: return "magnifyingglass"
        case .notifications: return "bell.fill"
        case .releases: return "shippingbox.fill"
        case .tags: return "tag.fill"
        case .issues: return "exclamationmark.bubble.fill"
        case .gitBlame: return "eye.circle"
        case .repositoryExplorer: return "folder.circle.fill"
        case .repositoryAutomationBuilder: return "arrow.triangle.2.circlepath.circle.fill"
        case .swiftCodeWorkflows: return "bolt.circle.fill"
        case .diffViewer: return "arrow.left.and.right.square"
        case .cli: return "terminal.fill"
        case .repositorySettings: return "gearshape.fill"
        case .onboarding: return "person.badge.key.fill"
        }
    }
}

// MARK: - Native Split View Controller
public class SourceControlSplitViewController: NSSplitViewController {
    public let gitViewModel: GitViewModel
    public let project: Project

    private var sidebarItem: NSSplitViewItem?
    private var mainItem: NSSplitViewItem?

    public init(gitViewModel: GitViewModel, project: Project) {
        self.gitViewModel = gitViewModel
        self.project = project
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // Sidebar Panel (Pure AppKit OutlineView Controller)
        let sidebarVC = SourceControlSidebarViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow + 10
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        // Main Workspace (SwiftUI View Wrapper)
        let mainView = SourceControlMainWrapper(gitViewModel: gitViewModel, project: project)
            .environment(ProjectSessionStore.shared)
            .environmentObject(AppSettings.shared)
        let mainVC = NSHostingController(rootView: StylingBootstrap.configureEnvironment(mainView))
        mainVC.sizingOptions = []
        mainVC.view.autoresizingMask = [.width, .height]
        let mainItem = NSSplitViewItem(viewController: mainVC)
        mainItem.minimumThickness = 700
        mainItem.holdingPriority = .defaultLow - 10
        self.mainItem = mainItem
        addSplitViewItem(mainItem)
    }
}

// MARK: - AppKit Sidebar Selection State
@Observable
@MainActor
final class SourceControlSidebarState {
    static let shared = SourceControlSidebarState()
    var selection: SourceControlSelection = .localWorkspace
    private init() {}
}

// MARK: - Native Sidebar View Controller
public class SourceControlSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private var scrollView: NSScrollView?
    private var outlineView: NSOutlineView?
    private let nodes: [SourceControlSidebarNode]

    public init() {
        self.nodes = buildSourceControlSidebarNodes()
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        self.scrollView = scroll

        let outline = NSOutlineView()
        outline.autoresizingMask = [.width]
        outline.headerView = nil
        outline.selectionHighlightStyle = .sourceList
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .custom
        outline.indentationPerLevel = 14
        self.outlineView = outline

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SourceControlColumn"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.dataSource = self
        outline.delegate = self

        scroll.documentView = outline
        visualEffectView.addSubview(scroll)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 40),
            scroll.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        self.view = visualEffectView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        if let outline = outlineView {
            for group in nodes {
                outline.expandItem(group)
            }
        }
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return nodes.count
        }
        if let node = item as? SourceControlSidebarNode {
            return node.children.count
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return nodes[index]
        }
        guard let node = item as? SourceControlSidebarNode else { return SourceControlSidebarNode(title: "") }
        return node.children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? SourceControlSidebarNode {
            return node.isGroup
        }
        return false
    }

    // MARK: - NSOutlineViewDelegate

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let node = item as? SourceControlSidebarNode {
            return node.isGroup
        }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let node = item as? SourceControlSidebarNode {
            return !node.isGroup
        }
        return true
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let node = item as? SourceControlSidebarNode, node.isGroup {
            return 26
        }
        return 32
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SourceControlSidebarNode else { return nil }

        if node.isGroup {
            let identifier = NSUserInterfaceItemIdentifier("SourceControlHeaderView")
            var textField = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            if textField == nil {
                textField = NSTextField(labelWithString: node.title)
                textField?.identifier = identifier
                textField?.font = .systemFont(ofSize: 11, weight: .bold)
                textField?.textColor = .headerTextColor
            } else {
                textField?.stringValue = node.title
            }
            return textField
        } else {
            let identifier = NSUserInterfaceItemIdentifier("SourceControlCell")
            var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SourceControlSidebarCellView
            if cell == nil {
                cell = SourceControlSidebarCellView(frame: .zero)
                cell?.identifier = identifier
            }

            cell?.textField?.stringValue = node.title
            if let iconName = node.icon {
                if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    cell?.iconView.image = image
                } else {
                    cell?.iconView.image = nil
                }
            } else {
                cell?.iconView.image = nil
            }
            cell?.iconView.contentTintColor = .controlAccentColor

            return cell
        }
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline = outlineView else { return }
        let selectedRow = outline.selectedRow
        if selectedRow >= 0, let node = outline.item(atRow: selectedRow) as? SourceControlSidebarNode, let selection = node.selection {
            SourceControlSidebarState.shared.selection = selection
        }
    }
}

// MARK: - AppKit Sidebar Helpers & Nodes
public final class SourceControlSidebarNode: NSObject {
    public let title: String
    public let icon: String?
    public let selection: SourceControlSelection?
    public let isGroup: Bool
    public var children: [SourceControlSidebarNode] = []

    public init(title: String, icon: String? = nil, selection: SourceControlSelection? = nil, isGroup: Bool = false) {
        self.title = title
        self.icon = icon
        self.selection = selection
        self.isGroup = isGroup
    }
}

class SourceControlSidebarCellView: NSTableCellView {
    let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        addSubview(text)
        self.textField = text

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

func buildSourceControlSidebarNodes() -> [SourceControlSidebarNode] {
    var nodes: [SourceControlSidebarNode] = []

    // 1. LOCAL WORKSPACE
    let workspace = SourceControlSidebarNode(title: "LOCAL WORKSPACE", isGroup: true)
    workspace.children = [
        SourceControlSidebarNode(title: "Dashboard", icon: "laptopcomputer", selection: .localWorkspace),
        SourceControlSidebarNode(title: "Changes", icon: "doc.badge.plus", selection: .changes),
        SourceControlSidebarNode(title: "Diff Viewer", icon: "arrow.left.and.right.square", selection: .diffViewer),
        SourceControlSidebarNode(title: "Git Worktrees", icon: "arrow.triangle.branch", selection: .gitWorktrees),
        SourceControlSidebarNode(title: "CLI", icon: "terminal.fill", selection: .cli)
    ]
    nodes.append(workspace)

    // 2. REPOSITORY
    let repo = SourceControlSidebarNode(title: "REPOSITORY", isGroup: true)
    repo.children = [
        SourceControlSidebarNode(title: "Branches", icon: "arrow.triangle.branch", selection: .branches),
        SourceControlSidebarNode(title: "Commit History", icon: "clock.arrow.circlepath", selection: .commitHistory),
        SourceControlSidebarNode(title: "Tags", icon: "tag.fill", selection: .tags),
        SourceControlSidebarNode(title: "Releases", icon: "shippingbox.fill", selection: .releases)
    ]
    nodes.append(repo)

    // 3. GITHUB INTEGRATION
    let github = SourceControlSidebarNode(title: "GITHUB INTEGRATION", isGroup: true)
    github.children = [
        SourceControlSidebarNode(title: "GitHub Account", icon: "person.crop.circle.fill", selection: .githubAccount),
        SourceControlSidebarNode(title: "Pull Requests", icon: "arrow.triangle.pull", selection: .pullRequests),
        SourceControlSidebarNode(title: "Issues", icon: "exclamationmark.bubble.fill", selection: .issues),
        SourceControlSidebarNode(title: "Actions", icon: "play.circle.fill", selection: .actions),
        SourceControlSidebarNode(title: "Discussions", icon: "bubble.left.and.bubble.right.fill", selection: .discussions),
        SourceControlSidebarNode(title: "Notifications", icon: "bell.fill", selection: .notifications),
        SourceControlSidebarNode(title: "GitHub Search", icon: "magnifyingglass", selection: .githubCodeSearch),
        SourceControlSidebarNode(title: "Repository Settings", icon: "gearshape.fill", selection: .repositorySettings)
    ]
    nodes.append(github)

    // 4. REPOSITORY INTELLIGENCE
    let intel = SourceControlSidebarNode(title: "REPOSITORY INTELLIGENCE", isGroup: true)
    intel.children = [
        SourceControlSidebarNode(title: "Intelligence", icon: "chart.bar.doc.horizontal", selection: .repositoryIntelligence),
        SourceControlSidebarNode(title: "Knowledge Graph", icon: "circle.grid.3x3", selection: .knowledgeGraph),
        SourceControlSidebarNode(title: "Timeline", icon: "calendar.day.timeline.left", selection: .repositoryTimeline),
        SourceControlSidebarNode(title: "Security Center", icon: "shield.righthalf.filled", selection: .securityCenter)
    ]
    nodes.append(intel)

    return nodes
}

// MARK: - SourceControl SwiftUI Main Wrapper
struct SourceControlMainWrapper: View {
    let gitViewModel: GitViewModel
    let project: Project

    @State private var successMessage: String?
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        let state = SourceControlSidebarState.shared
        Group {
            switch state.selection {
            case .gitWorktrees:
                GitWorktreesView()
            case .localWorkspace:
                RepositoryDashboardView(gitViewModel: gitViewModel, project: project) { _ in }
            case .changes:
                RepositoriesView(
                    gitViewModel: gitViewModel,
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .branches:
                BranchesView(
                    gitViewModel: gitViewModel,
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .commitHistory:
                CommitsView(gitViewModel: gitViewModel)
            case .pullRequests:
                PullRequestsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .github:
                OrganizationsView()
            case .actions:
                ActionsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .activityFeed:
                ActivityFeedView(project: project)
            case .discussions:
                DiscussionsView(project: project)
            case .githubAccount:
                GitHubAccountView()
            case .githubCodeSearch:
                GitHubCodeSearchView(project: project)
            case .notifications:
                NotificationsView()
            case .releases:
                ReleasesView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .tags:
                TagsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .issues:
                IssuesView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .gitBlame:
                GitBlameViewer(gitViewModel: gitViewModel)
            case .diffViewer:
                UnifiedDiffView(gitViewModel: gitViewModel)
            case .cli:
                GitCLIView(project: project)
            case .repositoryExplorer:
                RepositoryExplorerView(gitViewModel: gitViewModel, project: project)
            case .repositoryAutomationBuilder:
                RepositoryAutomationBuilderView(project: project)
            case .swiftCodeWorkflows:
                WorkflowDashboardView(project: project, gitViewModel: gitViewModel)
            case .repositorySettings:
                GitHubSettingsView(project: project)
            case .onboarding:
                SCSetupOnboard()
            case .repositoryIntelligence:
                RepositoryIntelligenceView(gitViewModel: gitViewModel)
            case .knowledgeGraph:
                RepositoryKnowledgeGraphView(gitViewModel: gitViewModel)
            case .repositoryTimeline:
                InteractiveRepositoryTimelineView(gitViewModel: gitViewModel)
            case .gitOperations:
                AdvancedGitOperationsCenterView(gitViewModel: gitViewModel)
            case .advancedDiff:
                AdvancedDiffCenterView(gitViewModel: gitViewModel)
            case .repositorySearch:
                RepositorySearchPlatformView(gitViewModel: gitViewModel)
            case .codeOwnership:
                CodeOwnershipWorkspaceView(gitViewModel: gitViewModel)
            case .branchIntelligence:
                BranchIntelligenceView(gitViewModel: gitViewModel)
            case .commitIntelligence:
                CommitIntelligenceView(gitViewModel: gitViewModel)
            case .pullRequestIntelligence:
                PullRequestIntelligenceView()
            case .securityCenter:
                SecurityCenterView()
            case .collaborationCenter:
                CollaborationCenterView()
            case .workspaceAutomation:
                WorkspaceAutomationView()
            case .githubDiscovery:
                GitHubDiscoveryView()
            case .aiAssistant:
                AIRepositoryAssistantView()
            }
        }
        .sourceControlEmbedded()
        .alert("Success", isPresented: $showSuccess, presenting: successMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
    }
}

// MARK: - Reconstructed SourceControlView SwiftUI Fallback (Shorthand Sheet Fallback)
@MainActor
public struct SourceControlView: View {
    var gitViewModel: GitViewModel
    @Environment(ProjectSessionStore.self) private var sessionStore

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                if let project = sessionStore.activeProject {
                    SourceControlWindowManager.shared.showWindow(for: project, gitViewModel: gitViewModel)
                }
            }
    }
}

// ====================================================================
// UNIFIED DIFF VIEW
// ====================================================================
struct UnifiedDiffView: View {
    var gitViewModel: GitViewModel
    @State private var hunks: [GitDiffHunk] = []
    @State private var isLoading = false

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading unified diff...")
            } else {
                GitDiffView(hunks: hunks)
            }
        }
        .onAppear {
            isLoading = true
            Task {
                hunks = await gitViewModel.getDiff()
                isLoading = false
            }
        }
    }
}
