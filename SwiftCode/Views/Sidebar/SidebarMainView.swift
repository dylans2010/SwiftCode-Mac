import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case files = "folder"
    case git = "sourcecontrol"
    case search = "magnifyingglass"
    case debug = "ant"
    case debugSessions = "play.square"
    case breakpoints = "breakpoint"
    case bookmarks = "bookmark"
    case tests = "checklist"
    case githubWorkflows = "square.stack.3d.down.right"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .git: return "Source Control"
        case .search: return "Search"
        case .debug: return "Debug Inspector"
        case .debugSessions: return "Debug Sessions"
        case .breakpoints: return "Breakpoints"
        case .bookmarks: return "Bookmarks"
        case .tests: return "Tests"
        case .githubWorkflows: return "GitHub Workflows"
        }
    }
}

struct SidebarMainView: View {
    @State private var selectedItem: SidebarItem = .files
    @Bindable var workspaceViewModel: WorkspaceViewModel

    var body: some View {
        HStack(spacing: 0) {
            // Icon Sidebar
            VStack(spacing: 12) {
                ForEach(SidebarItem.allCases) { item in
                    Button(action: { selectedItem = item }) {
                        Image(systemName: item.rawValue)
                            .font(.system(size: 20))
                            .foregroundStyle(selectedItem == item ? .primary : .secondary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(selectedItem == item ? Color.accentColor.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
            }
            .padding(.vertical, 10)
            .frame(width: 50)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content View
            VStack {
                Text(selectedItem.title)
                    .font(.headline)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                Divider()

                switch selectedItem {
                case .files:
                    FileNavigatorSidebarView(viewModel: workspaceViewModel.projectTree)
                case .git:
                    GitSidebarView(viewModel: workspaceViewModel.git)
                case .search:
                    SearchSidebarView()
                case .debug:
                    DebugInspectorSidebarView()
                case .debugSessions:
                    DebugSessionsSidebarView()
                case .breakpoints:
                    BreakpointsSidebarView()
                case .bookmarks:
                    BookmarksSidebarView()
                case .tests:
                    TestsSidebarView()
                case .githubWorkflows:
                    GitHubWorkflowsSidebarView()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
