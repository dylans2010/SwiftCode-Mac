import SwiftUI

struct EditorView: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel

    @State private var editorMode: EditorMode = .visual

    enum EditorMode: String, CaseIterable, Identifiable {
        case visual = "Visual Editor"
        case raw = "Raw XML Editor"

        var id: String { rawValue }
    }

    private var isXcodeProj: Bool {
        guard let url = viewModel.activeDocument?.url else { return false }
        return url.pathExtension == "xcodeproj" || url.lastPathComponent == "project.pbxproj"
    }

    private var isInfoPlist: Bool {
        guard let url = viewModel.activeDocument?.url else { return false }
        return url.pathExtension == "plist" || url.lastPathComponent == "Info.plist"
    }

    private var isEntitlements: Bool {
        guard let url = viewModel.activeDocument?.url else { return false }
        return url.pathExtension == "entitlements"
    }

    private var isMarkdown: Bool {
        guard let url = viewModel.activeDocument?.url else { return false }
        return url.pathExtension == "md"
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

            // Switcher for plist / entitlements
            if isInfoPlist || isEntitlements {
                HStack {
                    Picker("Editor Mode", selection: $editorMode) {
                        ForEach(EditorMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                Divider()
            }

            if isXcodeProj, let model = xcodeProjModel {
                XcodeProjViewer(model: model)
            } else if isInfoPlist, let url = viewModel.activeDocument?.url, editorMode == .visual {
                let resolvedURL = url.lastPathComponent.contains("Unresolved") ? nil : url
                InfoPlistView(fileURL: resolvedURL)
            } else if isEntitlements, let url = viewModel.activeDocument?.url, editorMode == .visual {
                let resolvedURL = url.lastPathComponent.contains("Unresolved") ? nil : url
                EntitlementsEditorView(fileURL: resolvedURL)
            } else if isMarkdown, let url = viewModel.activeDocument?.url {
                MarkdownFileView(viewModel: viewModel, fileURL: url)
            } else {
                NativeTextView(viewModel: viewModel)
            }
        }
        .macDesktopOptimized()
    }
}
