import SwiftUI

struct WorkspaceView: View {
    @State var viewModel: WorkspaceViewModel
    @Environment(ThemeViewModel.self) var themeVM

    var body: some View {
        EditorTextView(workspaceViewModel: viewModel)
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
