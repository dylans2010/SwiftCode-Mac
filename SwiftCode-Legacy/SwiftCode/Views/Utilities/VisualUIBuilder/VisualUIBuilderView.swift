import SwiftUI

/// Main entry point for the Visual UI Builder.
/// Optimizes and routes the workspace to a native macOS AppKit split-view window.
public struct VisualUIBuilderView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Visual UI Builder Workspace")
                .font(.title)
                .bold()

            Text("The workspace has been optimized as a native macOS desktop utility with persistent split panels, custom drag constraints, and multi-window environments.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: openWorkspace) {
                Label("Launch Workspace", systemImage: "arrow.up.forward.app")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            openWorkspace()
        }
    }

    private func openWorkspace() {
        VisualUIBuilderWindowManager.shared.showWindow()
        dismiss()
    }
}
