import SwiftUI

struct WorkspaceView: View {
    @State var viewModel: WorkspaceViewModel
    @Environment(ThemeViewModel.self) var themeVM
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectNavigatorView(viewModel: viewModel.projectTree)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } content: {
            EditorView(viewModel: viewModel.editor)
        } detail: {
            AIAssistantPanelView(viewModel: viewModel.ai, editorViewModel: viewModel.editor)
                .navigationSplitViewColumnWidth(min: 300, ideal: 350)
        }
        .toolbar {
            BuildToolbarView(viewModel: viewModel.build, projectURL: viewModel.projectURL)
            ToolbarItem {
                Button(action: { /* Toggle logic */ }) {
                    Label("Console", systemImage: "terminal")
                }
            }
        }
        .background(Color(hex: themeVM.currentTheme.background))
        .foregroundStyle(Color(hex: themeVM.currentTheme.foreground))
    }
}
