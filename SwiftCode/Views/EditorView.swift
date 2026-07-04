import SwiftUI

struct EditorView: View {
    @State var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBarView(viewModel: viewModel)
            if viewModel.activeDocument != nil {
                NativeTextView(viewModel: viewModel)
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc")
            }
        }
    }
}
