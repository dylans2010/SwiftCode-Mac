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
    case notifications = "Notifications"
    case settings = "Settings"

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
        case .notifications: return "bell.fill"
        case .settings: return "gearshape.fill"
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
        case .notifications: return .yellow
        case .settings: return .gray
        }
    }
}

@MainActor
struct GitHubSidebar: View {
    @Binding var selection: GitHubSidebarItem

    var body: some View {
        List(selection: $selection) {
            Section("Navigation") {
                ForEach(GitHubSidebarItem.allCases) { item in
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
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200, idealWidth: 220)
    }
}
