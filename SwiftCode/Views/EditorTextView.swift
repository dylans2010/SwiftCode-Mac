import SwiftUI

struct EditorTextView: View {
    @Bindable var workspaceViewModel: WorkspaceViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarMainView(workspaceViewModel: workspaceViewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            EditorView(viewModel: workspaceViewModel.editor)
        }
    }
}
