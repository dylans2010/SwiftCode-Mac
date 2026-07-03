import SwiftUI

struct ProjectNavigatorView: View {
    @State var viewModel: ProjectTreeViewModel

    var body: some View {
        List {
            if let root = viewModel.rootNode {
                OutlineGroup(root, children: \.children) { node in
                    ProjectTreeRowView(node: node)
                }
            } else {
                Text("No project open")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
    }
}
