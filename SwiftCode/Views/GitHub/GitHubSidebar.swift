import SwiftUI

enum GitHubSidebarItem: String, CaseIterable, Identifiable, Codable {
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
    case diffViewer = "Diff Viewer"
    case cli = "CLI"
    case githubAccount = "GitHub Account"
    case githubCodeSearch = "GitHub Code Search"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .repositories: return "folder.fill"
        case .organizations: return "building.2.fill"
        case .pullRequests: return "arrow.triangle.pull"
        case .issues: return "exclamationmark.bubble.fill"
        case .actions: return "play.circle.fill"
        case .branches: return "arrow.triangle.branch"
        case .commits: return "clock.arrow.circlepath"
        case .tags: return "tag.fill"
        case .releases: return "shippingbox.fill"
        case .discussions: return "bubble.left.and.bubble.right.fill"
        case .notifications: return "bell.fill"
        case .settings: return "gearshape.fill"
        case .diffViewer: return "arrow.left.and.right.square"
        case .cli: return "terminal.fill"
        case .githubAccount: return "person.crop.circle.fill"
        case .githubCodeSearch: return "magnifyingglass"
        }
    }

    var accentColor: Color {
        switch self {
        case .dashboard: return .blue
        case .repositories: return .orange
        case .organizations: return .purple
        case .pullRequests: return .green
        case .issues: return .red
        case .actions: return .cyan
        case .branches: return .blue
        case .commits: return .orange
        case .tags: return .purple
        case .releases: return .green
        case .discussions: return .indigo
        case .notifications: return .yellow
        case .settings: return .gray
        case .diffViewer: return .blue
        case .cli: return .gray
        case .githubAccount: return .purple
        case .githubCodeSearch: return .teal
        }
    }
}

@MainActor
struct GitHubSidebar: View {
    @Binding var selection: GitHubSidebarItem

    var body: some View {
        List(selection: $selection) {
            Section("Local Workspace") {
                sidebarRow(for: .dashboard)
                sidebarRow(for: .repositories)
                sidebarRow(for: .branches)
                sidebarRow(for: .commits)
                sidebarRow(for: .diffViewer)
                sidebarRow(for: .cli)
            }

            Section("GitHub Collaboration") {
                sidebarRow(for: .pullRequests)
                sidebarRow(for: .issues)
                sidebarRow(for: .actions)
                sidebarRow(for: .discussions)
                sidebarRow(for: .releases)
                sidebarRow(for: .tags)
            }

            Section("GitHub Intelligence") {
                sidebarRow(for: .githubCodeSearch)
                sidebarRow(for: .notifications)
                sidebarRow(for: .organizations)
            }

            Section("Account & Config") {
                sidebarRow(for: .githubAccount)
                sidebarRow(for: .settings)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 220)
    }

    @ViewBuilder
    private func sidebarRow(for item: GitHubSidebarItem) -> some View {
        NavigationLink(value: item) {
            Label {
                Text(item.rawValue)
                    .font(.body)
            } icon: {
                Image(systemName: item.icon)
                    .foregroundStyle(item.accentColor)
            }
        }
        .tag(item)
    }
}
