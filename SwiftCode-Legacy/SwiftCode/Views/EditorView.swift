import SwiftUI

public extension Notification.Name {
    static let specialEditorActive = Notification.Name("com.swiftcode.specialEditorActive")
}

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

    private var isSwiftCodeJSON: Bool {
        guard let url = viewModel.activeDocument?.url else { return false }
        return url.lastPathComponent == "swiftcode.json"
    }

    private var isXCStrings: Bool {
        guard let url = viewModel.activeDocument?.url else { return false }
        return url.pathExtension == "xcstrings"
    }

    private var xcodeProjModel: XcodeProjModel? {
        guard let url = viewModel.activeDocument?.url else { return nil }
        if let cached = workspaceViewModel.parsedXcodeProjects[url] {
            return cached
        }
        if let model = try? XcodeProjParse.shared.parse(projectURL: url) {
            workspaceViewModel.parsedXcodeProjects[url] = model
            return model
        }
        return nil
    }

    var body: some View {
        Group {
            if viewModel.activeDocument == nil {
                ContentUnavailableView {
                    Label("No File Selected", systemImage: "doc")
                } description: {
                    Text("Select a file from the navigator to start editing.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    EditorTabBarView(viewModel: viewModel)

                    editorJumpBar

                    if isInfoPlist || isEntitlements || isXCStrings {
                        editorModeBar
                        Divider()
                    }

                    editorContent
                }
            }
        }
        .macDesktopOptimized()
    }

    private var editorJumpBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let doc = viewModel.activeDocument {
                    Text(doc.url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(doc.url.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if doc.isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 7, height: 7)
                            .help("Unsaved changes")
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
            Divider()
        }
    }

    private var editorModeBar: some View {
        HStack(spacing: 12) {
            Label("Editor Mode", systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Picker("Editor Mode", selection: $editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))
    }

    @ViewBuilder
    private var editorContent: some View {
        if isXcodeProj, let model = xcodeProjModel {
            XcodeProjViewer(model: model)
        } else if isInfoPlist, let url = viewModel.activeDocument?.url, editorMode == .visual {
            let resolvedURL = url.lastPathComponent.contains("Unresolved") ? nil : url
            InfoPlistView(fileURL: resolvedURL)
        } else if isEntitlements, let url = viewModel.activeDocument?.url, editorMode == .visual {
            let resolvedURL = url.lastPathComponent.contains("Unresolved") ? nil : url
            EntitlementsEditorView(fileURL: resolvedURL)
        } else if isXCStrings, let url = viewModel.activeDocument?.url, editorMode == .visual {
            LocalizingAppNewView(fileURL: url)
        } else if isSwiftCodeJSON, let url = viewModel.activeDocument?.url {
            SwiftCodeJSONView(fileURL: url)
        } else if isMarkdown, let url = viewModel.activeDocument?.url {
            MarkdownFileView(viewModel: viewModel, fileURL: url)
        } else {
            NativeTextView(viewModel: viewModel)
        }
    }
}
