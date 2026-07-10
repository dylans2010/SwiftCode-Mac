import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel

    private var isXcodeProj: Bool {
        guard let url = viewModel.activeDocument?.url else { return false }
        return url.pathExtension == "xcodeproj" || url.lastPathComponent == "project.pbxproj"
    }

    private var xcodeProjModel: XcodeProjModel? {
        guard let url = viewModel.activeDocument?.url else { return nil }
        if let cached = workspaceViewModel.parsedXcodeProjects[url] {
            return cached
        }
        // Fallback parse on-the-fly
        if let model = try? XcodeProjParse.shared.parse(projectURL: url) {
            workspaceViewModel.parsedXcodeProjects[url] = model
            return model
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBarView(viewModel: viewModel)
            if isXcodeProj, let model = xcodeProjModel {
                XcodeProjViewer(model: model)
            } else {
                NativeTextView(viewModel: viewModel)
            }
        }
        .macDesktopOptimized()
    }
}
