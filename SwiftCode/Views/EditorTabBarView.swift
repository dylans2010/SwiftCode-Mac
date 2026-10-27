import SwiftUI

struct EditorTabBarView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.openDocuments) { doc in
                    HStack(spacing: 6) {
                        Image(systemName: doc.url.pathExtension == "swift" ? "swift" : "doc.text")
                            .font(.caption)
                            .foregroundStyle(doc.url.pathExtension == "swift" ? .orange : .secondary)
                        Text(doc.url.lastPathComponent)
                            .font(.subheadline)
                        Button(action: { closeTab(doc) }) {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Group {
                            if viewModel.selectedTabID == doc.id {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.16))
                                    .overlay(SpecularBorder(cornerRadius: 6, lineWidth: 1))
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                    .onTapGesture {
                        viewModel.selectedTabID = doc.id
                        viewModel.activeDocument = doc
                    }
                    Divider()
                        .frame(height: 16)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 35)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
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
