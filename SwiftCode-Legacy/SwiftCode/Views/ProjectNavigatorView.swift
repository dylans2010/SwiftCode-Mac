import SwiftUI

struct ProjectNavigatorView: View {
    @Bindable var viewModel: ProjectTreeViewModel

    var body: some View {
        FileNavigatorSidebarView(viewModel: viewModel)
    }
}
