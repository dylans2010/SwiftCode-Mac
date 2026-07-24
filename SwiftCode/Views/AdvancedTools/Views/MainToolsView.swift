import SwiftUI

struct WorkspaceHubTool: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let iconName: String
    let colorHex: String
    let category: String
    let destination: String
}

public struct MainToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    public init() {}

    // Static baseline definition of all tools migrated from WorkspaceView, including DocumentationBrowser
    private let allAvailableTools: [WorkspaceHubTool] = [
        WorkspaceHubTool(id: "terminal", name: "Terminal Console", description: "Open local shells, run background commands, manage SSH nodes, and configure terminal themes.", iconName: "terminal.fill", colorHex: "#5AC8FA", category: "Utilities", destination: "terminal"),
        WorkspaceHubTool(id: "build_settings", name: "Xcode Build Settings", description: "Manage optimization levels, target SDKs, and build parameters.", iconName: "gearshape.2.fill", colorHex: "#34C759", category: "Build & Deploy", destination: "xcodeBuildSettings"),
        WorkspaceHubTool(id: "build_logs", name: "Xcode Build Logs", description: "Stream compile warnings, errors, and live build output.", iconName: "doc.text.fill", colorHex: "#FF9500", category: "Build & Deploy", destination: "xcodeBuildLogs"),
        WorkspaceHubTool(id: "ipa_builder", name: "IPA Packaging Suite", description: "Pack built iOS apps into IPA containers from SwiftCode without Xcode UI.", iconName: "shippingbox.fill", colorHex: "#AF52DE", category: "Build & Deploy", destination: "ipaBuild"),
        WorkspaceHubTool(id: "deployments", name: "Deployments Console", description: "Trigger production deployments to Netlify, Vercel, and GitHub Pages.", iconName: "cloud.fill", colorHex: "#5AC8FA", category: "Build & Deploy", destination: "deployments"),
        WorkspaceHubTool(id: "dependency_manager", name: "Dependency Manager", description: "Search, import, and manage local or remote Swift packages.", iconName: "puzzlepiece.extension.fill", colorHex: "#007AFF", category: "Utilities", destination: "dependencyManager"),
        WorkspaceHubTool(id: "source_control", name: "Source Control", description: "Inspect Git history, commits, stashes, merges, and conflicts.", iconName: "square.stack.3d.down.right.fill", colorHex: "#4CD964", category: "Git & CI", destination: "sourceControl"),
        WorkspaceHubTool(id: "ci_build", name: "CI Visual Workflows", description: "Create and monitor GitHub Actions workflow runners visually.", iconName: "play.circle.fill", colorHex: "#5856D6", category: "Git & CI", destination: "ciBuild"),
        WorkspaceHubTool(id: "simulator_main", name: "Simulator & Previews", description: "Simulate devices, manage simulators, and inspect preview screens.", iconName: "iphone", colorHex: "#FF2D55", category: "Utilities", destination: "simulatorMain"),
        WorkspaceHubTool(id: "personal_documentation", name: "Personal Documentation", description: "Access personal markdown wikis, notes, and local code references.", iconName: "book.fill", colorHex: "#A2845E", category: "Utilities", destination: "personalDocumentation"),
        WorkspaceHubTool(id: "dev_tools", name: "Developer utility bundle", description: "JSON formatters, base64 encoders, regex checkers, and JWT tools.", iconName: "wrench.and.screwdriver.fill", colorHex: "#FF3B30", category: "Utilities", destination: "devTools"),
        WorkspaceHubTool(id: "collaboration", name: "Live Collaboration", description: "Coordinate real-time coding sessions with team members.", iconName: "person.2.fill", colorHex: "#34C759", category: "Utilities", destination: "collaboration"),
        WorkspaceHubTool(id: "sf_symbols", name: "SF Symbols Browser", description: "Search and copy native SF Symbol identifiers.", iconName: "sparkles", colorHex: "#FFCC00", category: "Utilities", destination: "sfSymbolsBrowser"),
        WorkspaceHubTool(id: "extension_marketplace", name: "Extension Marketplace", description: "Browse and install community tools, themes, and extensions.", iconName: "bag.fill", colorHex: "#AF52DE", category: "Utilities", destination: "extensionMarketplace"),
        WorkspaceHubTool(id: "crash_log_analyzer", name: "Crash Log Analyzer", description: "Analyze production crash logs and trace symbolic memory leaks.", iconName: "doc.richtext.fill", colorHex: "#FF3B30", category: "Utilities", destination: "crashLogAnalyzer"),
        WorkspaceHubTool(id: "project_dependency_graph", name: "Project Dependency Graph", description: "Render internal project file import mapping and graphs.", iconName: "network", colorHex: "#007AFF", category: "Utilities", destination: "projectDependencyGraph"),
        WorkspaceHubTool(id: "workspace_profiles", name: "Workspace Profiles", description: "Create, edit, duplicate, and switch between workspace setting profiles.", iconName: "person.crop.square.fill.and.at.rectangle.fill", colorHex: "#34C759", category: "Utilities", destination: "workspaceProfiles"),
        WorkspaceHubTool(id: "snippets_library", name: "Snippets Library", description: "Store, tag, categorize, and quickly insert code snippet templates.", iconName: "curlybraces", colorHex: "#FF9500", category: "Utilities", destination: "snippetsLibrary"),
        WorkspaceHubTool(id: "documentation_browser", name: "Documentation Browser", description: "Full featured windowed multi-pane documentation browser and visual reference workspace.", iconName: "doc.text.magnifyingglass", colorHex: "#007AFF", category: "Utilities", destination: "documentationBrowser")
    ]

    private var filteredCategories: [String] {
        let cats = Set(allAvailableTools.map { $0.category })
        return Array(cats).sorted()
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Search Bar
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Search Workspace Tools", systemImage: "magnifyingglass")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Type to search tools...", text: $searchQuery)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()

                                if !searchQuery.isEmpty {
                                    Button {
                                        searchQuery = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Tool Category GroupBoxes matching DeploymentsView
                    ForEach(filteredCategories, id: \.self) { category in
                        let categoryTools = toolsForCategory(category)
                        if !categoryTools.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Label(category, systemImage: iconForCategory(category))
                                            .font(.headline)
                                            .foregroundColor(colorForCategory(category))
                                        Spacer()
                                    }

                                    VStack(spacing: 16) {
                                        ForEach(categoryTools) { tool in
                                            HStack(spacing: 12) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color(hex: tool.colorHex).opacity(0.12))
                                                        .frame(width: 36, height: 32)
                                                    Image(systemName: tool.iconName)
                                                        .font(.title3)
                                                        .foregroundStyle(Color(hex: tool.colorHex))
                                                }

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(tool.name)
                                                        .font(.subheadline.bold())
                                                        .foregroundStyle(.primary)
                                                    Text(tool.description)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(2)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }

                                                Spacer()

                                                Button("Open Tool") {
                                                    launchTool(tool)
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.regular)
                                            }

                                            if tool != categoryTools.last {
                                                Divider()
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Workspace Tools Hub")
        }
    }

    private func toolsForCategory(_ category: String) -> [WorkspaceHubTool] {
        let categoryList = allAvailableTools.filter { $0.category == category }
        if searchQuery.isEmpty {
            return categoryList
        } else {
            return categoryList.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                $0.description.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Build & Deploy": return "hammer.fill"
        case "Git & CI": return "arrow.triangle.branch"
        case "Utilities": return "wrench.and.screwdriver.fill"
        default: return "gearshape.fill"
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Build & Deploy": return .orange
        case "Git & CI": return .green
        case "Utilities": return .blue
        default: return .purple
        }
    }

    private func launchTool(_ tool: WorkspaceHubTool) {
        dismiss()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .toolbarToolActivated,
                object: nil,
                userInfo: ["toolID": tool.destination]
            )
        }
    }
}
