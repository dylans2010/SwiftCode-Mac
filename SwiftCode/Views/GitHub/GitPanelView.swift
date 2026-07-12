import SwiftUI

struct GitPanelView: View {
    @State var viewModel: GitViewModel
    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Segmented picker card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Git Workspace Navigation", systemImage: "arrow.triangle.branch")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        Picker("", selection: $selectedTab) {
                            Text("Changes").tag(0)
                            Text("History").tag(1)
                            Text("Branches").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Selected Tab view card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label(tabTitle(selectedTab), systemImage: tabIcon(selectedTab))
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        switch selectedTab {
                        case 0:
                            GitChangesView(viewModel: viewModel)
                        case 1:
                            GitHistoryView(commits: viewModel.history)
                        case 2:
                            GitBranchesView(branches: viewModel.branches)
                        default:
                            EmptyView()
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func tabTitle(_ tab: Int) -> String {
        switch tab {
        case 0: return "Workspace Unstaged Changes"
        case 1: return "Commit History Logs"
        case 2: return "Branch Directory"
        default: return ""
        }
    }

    private func tabIcon(_ tab: Int) -> String {
        switch tab {
        case 0: return "plus.minus.circle"
        case 1: return "clock.arrow.circlepath"
        case 2: return "arrow.triangle.branch"
        default: return ""
        }
    }
}
