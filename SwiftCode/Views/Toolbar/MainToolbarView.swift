import SwiftUI

struct MainToolbarView: View {
    @EnvironmentObject private var projectManager: ProjectManager
    @EnvironmentObject private var toolbarSettings: ToolbarSettings
    @StateObject private var toolbarManager = ToolbarManager.shared
    @State private var showAllTools = false

    // Tools to show on the compact bar (pinned tools)
    private var pinnedTools: [ToolbarTool] {
        var tools = toolbarManager.enabledTools

        // Filter out deployments if not a web project
        if let project = projectManager.activeProject {
            let isWebProject = project.files.contains { node in
                isWebFile(node)
            }
            if !isWebProject {
                tools.removeAll { $0.id == "deployments" }
            }
        }

        return tools
    }

    private func isWebFile(_ node: FileNode) -> Bool {
        let webExtensions = [".html", ".css", ".js", ".jsx", ".ts", ".tsx", "package.json"]
        if webExtensions.contains(where: { node.name.lowercased().hasSuffix($0) }) {
            return true
        }
        if node.isDirectory {
            return node.children.contains { isWebFile($0) }
        }
        return false
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "All Tools" Button
                Button {
                    showAllTools.toggle()
                } label: {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.orange)
                        .frame(width: 40, height: 40)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.1))

                // Active File Info
                if let node = projectManager.activeFileNode {
                    HStack(spacing: 8) {
                        Image(systemName: node.icon)
                            .foregroundStyle(node.iconColor)
                            .font(.caption)
                        Text(node.name)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.1))

                // Editor Controls
                HStack(spacing: 12) {
                    Button {
                        projectManager.saveCurrentFile(content: projectManager.activeFileContent)
                    } label: {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Save (⌘S)")

                    Button {
                        toolbarSettings.wordWrap.toggle()
                    } label: {
                        Image(systemName: toolbarSettings.wordWrap ? "text.word.spacing" : "text.alignleft")
                            .font(.system(size: 16))
                            .foregroundStyle(toolbarSettings.wordWrap ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Word Wrap")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toolbarSettings.showSearchBar.toggle()
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundStyle(toolbarSettings.showSearchBar ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Search")
                }

                Divider()
                    .frame(height: 24)
                    .background(Color.white.opacity(0.1))

                // Quick Access Pinned Tools
                HStack(spacing: 14) {
                    ForEach(pinnedTools) { tool in
                        Button {
                            NotificationCenter.default.post(
                                name: .toolbarToolActivated,
                                object: nil,
                                userInfo: ["toolID": tool.id]
                            )
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 16))
                                    .foregroundStyle(iconColor(for: tool.id))

                                if toolbarSettings.showToolNames {
                                    Text(tool.name)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(minWidth: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(Divider().opacity(0.3), alignment: .bottom)
        .sheet(isPresented: $showAllTools) {
            ToolbarExpandedPanelView(isPresented: $showAllTools)
                .preferredColorScheme(.dark)
        }
    }

    private func iconColor(for toolId: String) -> Color {
        switch toolId {
        case "file_navigator": return .orange
        case "ai_code_gen": return .purple
        case "github_actions", "git_history": return .blue
        case "build_trigger", "build_status", "build_logs", "terminal": return .orange
        case "errors_viewer": return .red
        case "dependency_manager", "install_dependency": return .teal
        case "code_search", "symbol_navigator", "project_index", "go_to_line", "symbol_outline": return .cyan
        case "sf_symbols_browser": return .indigo
        case "local_simulation": return .green
        case "plugin_manager": return .pink
        case "file_preview": return .yellow
        case "deployments": return .orange
        case "run_tests": return .green
        case "gist_manager": return .purple
        case "assist_view": return .mint
        default: return .secondary
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        MainToolbarView()
    }
}
