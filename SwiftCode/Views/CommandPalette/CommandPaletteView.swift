import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    let onAction: (CommandAction) -> Void

    enum CommandAction: String, CaseIterable, Identifiable {
        case createFile = "Create File"
        case createFolder = "Create Folder"
        case searchProject = "Search Project"
        case runAgent = "Run AI Agent"
        case installDependency = "Install Dependency"
        case openSettings = "Open Settings"
        case runBuild = "Run Build"
        case goToLine = "Go To Line"
        case openSymbolNav = "Symbol Navigator"
        case openDiffViewer = "Diff Viewer"
        case openErrors = "View Errors"
        case openDependencies = "Manage Dependencies"
        case openBuildLogs = "Build Logs"
        case customizeToolbar = "Customize Toolbar"
        case openProjectSettings = "Project Settings"
        case openMinimap = "Minimap Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .createFile: return "doc.badge.plus"
            case .createFolder: return "folder.badge.plus"
            case .searchProject: return "magnifyingglass"
            case .runAgent: return "sparkles"
            case .installDependency: return "shippingbox.fill"
            case .openSettings: return "gearshape.fill"
            case .runBuild: return "hammer.fill"
            case .goToLine: return "arrow.right.to.line"
            case .openSymbolNav: return "list.bullet.indent"
            case .openDiffViewer: return "arrow.left.arrow.right"
            case .openErrors: return "exclamationmark.triangle.fill"
            case .openDependencies: return "shippingbox"
            case .openBuildLogs: return "doc.text.magnifyingglass"
            case .customizeToolbar: return "slider.horizontal.3"
            case .openProjectSettings: return "gearshape"
            case .openMinimap: return "map.fill"
            }
        }

        var shortcut: String {
            switch self {
            case .createFile: return "⌘N"
            case .searchProject: return "⌘⇧F"
            case .runBuild: return "⌘B"
            case .goToLine: return "⌘G"
            case .openSettings: return "⌘,"
            default: return ""
            }
        }
    }

    var filteredCommands: [CommandAction] {
        if searchText.isEmpty { return CommandAction.allCases }
        return CommandAction.allCases.filter {
            $0.rawValue.lowercased().contains(searchText.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(.orange)
                    TextField("Type A Command", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Divider().opacity(0.3).padding(.top, 8)

                // Commands list
                List(filteredCommands) { command in
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onAction(command)
                        }
                    } label: {
                        HStack {
                            Image(systemName: command.icon)
                                .foregroundStyle(.orange)
                                .frame(width: 24)
                            Text(command.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Spacer()
                            if !command.shortcut.isEmpty {
                                Text(command.shortcut)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(red: 0.10, green: 0.10, blue: 0.14))
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
