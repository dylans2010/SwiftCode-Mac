import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBarView(viewModel: viewModel)

            if let activeURL = viewModel.activeDocument?.url {
                BreadcrumbView(url: activeURL, projectRoot: ProjectManager.shared.activeProject?.directoryURL)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                Divider()
            }

            NativeTextView(viewModel: viewModel)
        }
        .macDesktopOptimized()
    }
}
