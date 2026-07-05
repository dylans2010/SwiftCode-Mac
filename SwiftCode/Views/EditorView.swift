import SwiftUI

struct EditorView: View {
    @State var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBarView(viewModel: viewModel)
            NativeTextView(viewModel: viewModel)
        }
    }
}
