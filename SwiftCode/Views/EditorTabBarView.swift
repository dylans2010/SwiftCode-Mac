import SwiftUI

struct EditorTabBarView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.openDocuments) { doc in
                    HStack {
                        Text(doc.url.lastPathComponent)
                        Button(action: { closeTab(doc) }) {
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(viewModel.selectedTabID == doc.id ? Color.secondary.opacity(0.2) : Color.clear)
                    .onTapGesture {
                        viewModel.selectedTabID = doc.id
                        viewModel.activeDocument = doc
                    }
                    Divider()
                }
            }
        }
        .frame(height: 35)
        .background(Color.secondary.opacity(0.1))
    }

    private func closeTab(_ doc: SourceFileDocument) {
        if let index = viewModel.openDocuments.firstIndex(where: { $0.id == doc.id }) {
            viewModel.openDocuments.remove(at: index)
            if viewModel.selectedTabID == doc.id {
                viewModel.activeDocument = viewModel.openDocuments.last
                viewModel.selectedTabID = viewModel.activeDocument?.id
            }
        }
    }
}
