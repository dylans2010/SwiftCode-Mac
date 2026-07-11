import SwiftUI

struct CommandPaletteView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: CommandCategory = .all

    let onAction: (CommandAction) -> Void

    enum CommandCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case files = "Files & Nav"
        case git = "Git"
        case ai = "AI"
        case build = "Build / Sign"
        case settings = "Settings"

        var id: String { rawValue }
    }

    enum CommandAction: String, CaseIterable, Identifiable {
        // Files & Nav
        case createFile = "Create File"
        case createFolder = "Create Folder"
        case searchProject = "Global Code Search"
        case goToLine = "Go To Line"
        case openSymbolNav = "Symbol Navigator"
        case openSystemOutline = "System Outline / Symbols"
        case openMinimap = "Minimap Settings"

        // Git
        case gitCommit = "Git Commit Changes"
        case gitPull = "Git Pull"
        case gitPush = "Git Push"
        case gitCheckout = "Git Checkout Branch"
        case gitNewBranch = "Git Create New Branch"
        case openDiffViewer = "Diff Viewer"

        // AI
        case runAgent = "Run AI Agent"
        case aiCodeReview = "AI Code Review"
        case aiComplexity = "AI Complexity Analyzer"

        // Build / Sign
        case runBuild = "Run Project Build"
        case openXcodeBuildSettings = "Xcode Build Settings"
        case openXcodeBuildLogs = "Xcode Build Logs"
        case appleSigning = "Apple Developer Account & Signing"

        // Settings / Tools
        case openSettings = "Open App Settings"
        case openProjectSettings = "Project Settings"
        case installDependency = "Manage Dependencies"
        case openPluginManager = "Plugin Manager"
        case openExtensionMarketplace = "Extension Marketplace"
        case customizeToolbar = "Customize Toolbar"

        var id: String { rawValue }

        var category: CommandCategory {
            switch self {
            case .createFile, .createFolder, .searchProject, .goToLine, .openSymbolNav, .openSystemOutline, .openMinimap:
                return .files
            case .gitCommit, .gitPull, .gitPush, .gitCheckout, .gitNewBranch, .openDiffViewer:
                return .git
            case .runAgent, .aiCodeReview, .aiComplexity:
                return .ai
            case .runBuild, .openXcodeBuildSettings, .openXcodeBuildLogs, .appleSigning:
                return .build
            case .openSettings, .openProjectSettings, .installDependency, .openPluginManager, .openExtensionMarketplace, .customizeToolbar:
                return .settings
            }
        }

        var icon: String {
            switch self {
            case .createFile: return "doc.badge.plus"
            case .createFolder: return "folder.badge.plus"
            case .searchProject: return "magnifyingglass"
            case .goToLine: return "arrow.right.to.line"
            case .openSymbolNav: return "list.bullet.indent"
            case .openSystemOutline: return "align.horizontal.left"
            case .openMinimap: return "map.fill"

            case .gitCommit: return "checkmark.circle"
            case .gitPull: return "arrow.down.circle"
            case .gitPush: return "arrow.up.circle"
            case .gitCheckout: return "arrow.branch"
            case .gitNewBranch: return "plus.circle"
            case .openDiffViewer: return "arrow.left.arrow.right"

            case .runAgent: return "sparkles"
            case .aiCodeReview: return "text.badge.checkmark"
            case .aiComplexity: return "chart.bar.xaxis"

            case .runBuild: return "hammer.fill"
            case .openXcodeBuildSettings: return "gearshape.2"
            case .openXcodeBuildLogs: return "doc.text.magnifyingglass"
            case .appleSigning: return "key"

            case .openSettings: return "gearshape.fill"
            case .openProjectSettings: return "gearshape"
            case .installDependency: return "shippingbox.fill"
            case .openPluginManager: return "cpu"
            case .openExtensionMarketplace: return "puzzlepiece.extension"
            case .customizeToolbar: return "slider.horizontal.3"
            }
        }

        var shortcut: String {
            switch self {
            case .createFile: return "⌘N"
            case .searchProject: return "⌘⇧F"
            case .runBuild: return "⌘B"
            case .goToLine: return "⌘G"
            case .openSettings: return "⌘,"
            case .runAgent: return "⌘⇧A"
            default: return ""
            }
        }
    }

    var filteredCommands: [CommandAction] {
        var cmds = CommandAction.allCases

        if selectedCategory != .all {
            cmds = cmds.filter { $0.category == selectedCategory }
        }

        if !searchText.isEmpty {
            cmds = cmds.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
        }

        return cmds
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search & Filter Category Bar
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(.orange)
                        TextField("Type a command...", text: $searchText)
                            .autocorrectionDisabled()
                            .textFieldStyle(.plain)

                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(CommandCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider().opacity(0.3)

                // Commands list
                List(filteredCommands) { command in
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
