import SwiftUI

enum MainSidebarItem: String, CaseIterable, Identifiable {
    case files = "folder"
    case git = "sourcecontrol"
    case search = "magnifyingglass"
    case debug = "ant"
    case agent = "bubble.left.and.exclamationmark.bubble.right.fill"
    case workflows = "square.stack.3d.down.right"
    case terminal = "terminal"
    // No extensions case: Extensions no longer lives in the
    // workspace sidebar. It opens from the code-editor toolbar
    // (WorkspaceView, next to the Assist button) as its own sheet,
    // so it gets full width instead of a squeezed sidebar column.

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .git: return "Source Control"
        case .search: return "Search"
        case .debug: return "Debug"
        case .agent: return "AI Agent"
        case .workflows: return "Workflows"
        case .terminal: return "Terminal"
        }
    }
}

struct SidebarMainView: View {
    @State private var selectedItem: MainSidebarItem = .files
    @Bindable var workspaceViewModel: WorkspaceViewModel
    @State private var isHovered: MainSidebarItem?

    var body: some View {
        HStack(spacing: 0) {
            // Icon Sidebar (Visual Sidebar)
            VStack(spacing: 12) {
                ForEach(MainSidebarItem.allCases) { item in
                    Button(action: { selectedItem = item }) {
                        Image(systemName: item.rawValue)
                            .font(.system(size: 18))
                            .foregroundStyle(selectedItem == item ? .primary : .secondary)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        Group {
                            if selectedItem == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.2))
                                    .overlay(SpecularBorder(cornerRadius: 8, lineWidth: 1))
                            } else if isHovered == item {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(SpecularBorder(cornerRadius: 8, lineWidth: 0.5, intensity: 0.5))
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .help(item.title)
                    .onHover { hovering in
                        isHovered = hovering ? item : nil
                    }
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .frame(width: 50)
            .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))

            Divider()

            // Content View (Actual Navigation Column Content)
            VStack(spacing: 0) {
                HStack {
                    Text(selectedItem.title)
                        .font(.headline)
                    Spacer()
                }
                .padding()
                .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

                Divider()

                Group {
                    switch selectedItem {
                    case .files:
                        FileNavigatorSidebarView(viewModel: workspaceViewModel.projectTree)
                    case .git:
                        GitSidebarView(viewModel: workspaceViewModel.git)
                    case .search:
                        SearchSidebarView()
                    case .debug:
                        DebugSessionsSidebarView(viewModel: workspaceViewModel.debug)
                    case .agent:
                        AssistMainView()
                    case .workflows:
                        GitHubWorkflowsSidebarView()
                    case .terminal:
                        TerminalView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SelectSidebarItem"))) { notification in
            if let itemString = notification.userInfo?["item"] as? String,
               let item = MainSidebarItem(rawValue: itemString) {
                selectedItem = item
            }
        }
        .environment(workspaceViewModel)
    }
}
