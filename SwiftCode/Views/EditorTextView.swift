import SwiftUI

struct EditorTextView: View {
    @Bindable var workspaceViewModel: WorkspaceViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarMainView(workspaceViewModel: workspaceViewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } content: {
            VStack(spacing: 0) {
                EditorToolbarView(viewModel: workspaceViewModel.editor)
                EditorView(viewModel: workspaceViewModel.editor)
            }
        } detail: {
            AIAssistantPanelView(viewModel: workspaceViewModel.ai, editorViewModel: workspaceViewModel.editor)
                .navigationSplitViewColumnWidth(min: 300, ideal: 350)
        }
    }
}

struct EditorToolbarView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        HStack {
            if let doc = viewModel.activeDocument {
                Text(doc.url.lastPathComponent)
                    .font(.subheadline)
                    .bold()
            }
            Spacer()

            HStack(spacing: 12) {
                Button(action: { /* Logic for terminal */ }) {
                    Label("Terminal", systemImage: "terminal")
                }
                Button(action: { /* Logic for debug */ }) {
                    Label("Debugger", systemImage: "ant")
                }
                Button(action: { /* Logic for AI */ }) {
                    Label("AI Fix", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}
