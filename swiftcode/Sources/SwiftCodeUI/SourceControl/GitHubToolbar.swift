import SwiftUI

/// Ported from SwiftCode-Legacy `SwiftCode/Views/GitHub/GitHubToolbar.swift`
/// (Dylan's own code; direct port authorised under MIT).
///
/// The GitHub workspace toolbar: the section picker plus the refresh / sync
/// actions for the connected project. Legacy's hardcoded dark paint is
/// replaced with system-adaptive styling; the callbacks are unchanged.
///
/// `GitHubSidebarItem` is defined here because no destination equivalent
/// exists (Legacy defined it in `GitHubSidebar.swift`, which has no port
/// yet). A future GitHub sidebar port should reuse this enum rather than
/// defining its own.
///
/// Hook: host this in the workspace toolbar bands
/// (`WorkspaceWindowController+ToolbarBand.swift` /
/// `+ToolbarRight.swift`) and wire the callbacks to the source-control
/// coordinator / GitHub actions (refresh → reload the GitHub views,
/// onPull/onPush/onFetch → `SourceControlCoordinator`, onClone →
/// `GitHistory.clone`, onNewBranch/onNewPullRequest/onNewIssue → the
/// corresponding creation sheets). Until then it is usable as a standalone
/// toolbar view with caller-supplied closures.
@MainActor
public struct GitHubToolbar: View {
    public var currentSelection: GitHubSidebarItem
    public var isProjectConnected: Bool
    public var isPerformingAction: Bool
    public var onSelectionChange: (GitHubSidebarItem) -> Void
    public var onRefresh: () -> Void
    public var onClone: () -> Void
    public var onPull: () -> Void
    public var onPush: () -> Void
    public var onFetch: () -> Void
    public var onSync: () -> Void
    public var onNewBranch: () -> Void
    public var onNewPullRequest: () -> Void
    public var onNewIssue: () -> Void

    public init(
        currentSelection: GitHubSidebarItem,
        isProjectConnected: Bool,
        isPerformingAction: Bool = false,
        onSelectionChange: @escaping (GitHubSidebarItem) -> Void,
        onRefresh: @escaping () -> Void,
        onClone: @escaping () -> Void,
        onPull: @escaping () -> Void,
        onPush: @escaping () -> Void,
        onFetch: @escaping () -> Void,
        onSync: @escaping () -> Void,
        onNewBranch: @escaping () -> Void,
        onNewPullRequest: @escaping () -> Void,
        onNewIssue: @escaping () -> Void
    ) {
        self.currentSelection = currentSelection
        self.isProjectConnected = isProjectConnected
        self.isPerformingAction = isPerformingAction
        self.onSelectionChange = onSelectionChange
        self.onRefresh = onRefresh
        self.onClone = onClone
        self.onPull = onPull
        self.onPush = onPush
        self.onFetch = onFetch
        self.onSync = onSync
        self.onNewBranch = onNewBranch
        self.onNewPullRequest = onNewPullRequest
        self.onNewIssue = onNewIssue
    }

    public var body: some View {
        HStack(spacing: 8) {
            Picker("Section", selection: Binding(
                get: { currentSelection },
                set: { onSelectionChange($0) }
            )) {
                ForEach(GitHubSidebarItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }
            }
            .pickerStyle(.menu)
            .disabled(isPerformingAction)

            Divider()

            Button(action: onRefresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(!isProjectConnected || isPerformingAction)

            Button(action: onClone) {
                Label("Clone", systemImage: "square.and.arrow.down")
            }
            .disabled(isPerformingAction)

            Divider()

            Button(action: onPull) {
                Label("Pull", systemImage: "arrow.down.to.line")
            }
            .disabled(!isProjectConnected || isPerformingAction)

            Button(action: onPush) {
                Label("Push", systemImage: "arrow.up.to.line")
            }
            .disabled(!isProjectConnected || isPerformingAction)

            Button(action: onFetch) {
                Label("Fetch", systemImage: "arrow.down.circle")
            }
            .disabled(!isProjectConnected || isPerformingAction)

            Button(action: onSync) {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!isProjectConnected || isPerformingAction)

            Divider()

            Menu {
                Button("New Branch…", action: onNewBranch)
                Button("New Pull Request…", action: onNewPullRequest)
                Button("New Issue…", action: onNewIssue)
            } label: {
                Label("New", systemImage: "plus")
            }
            .disabled(!isProjectConnected || isPerformingAction)

            if isPerformingAction {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 8)
    }
}

/// The GitHub workspace sections (Legacy `GitHubSidebar.swift` cases).
/// A future GitHub sidebar port should reuse this enum.
public enum GitHubSidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case repositories = "Repositories"
    case organizations = "Organizations"
    case pullRequests = "Pull Requests"
    case issues = "Issues"
    case actions = "Actions"
    case branches = "Branches"
    case commits = "Commits"
    case tags = "Tags"
    case releases = "Releases"
    case discussions = "Discussions"
    case notifications = "Notifications"
    case settings = "Settings"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .repositories: return "folder"
        case .organizations: return "building.2"
        case .pullRequests: return "arrow.triangle.pull"
        case .issues: return "exclamationmark.circle"
        case .actions: return "play.circle"
        case .branches: return "arrow.triangle.branch"
        case .commits: return "clock.arrow.circlepath"
        case .tags: return "tag"
        case .releases: return "shippingbox"
        case .discussions: return "bubble.left.and.bubble.right"
        case .notifications: return "bell"
        case .settings: return "gear"
        }
    }
}
