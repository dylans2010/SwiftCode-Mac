import SwiftUI

struct EditorTextView: View {
    @Bindable var workspaceViewModel: WorkspaceViewModel

    var body: some View {
        EditorView(viewModel: workspaceViewModel.editor)
    }
}
