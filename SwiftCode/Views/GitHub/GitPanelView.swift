import SwiftUI

struct GitPanelView: View {
    @State var viewModel: GitViewModel
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Changes").tag(0)
                Text("History").tag(1)
                Text("Branches").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(8)

            switch selectedTab {
            case 0: GitChangesView(viewModel: viewModel)
            case 1: GitHistoryView(commits: viewModel.history)
            case 2: GitBranchesView(branches: viewModel.branches)
            default: EmptyView()
            }
        }
    }
}
