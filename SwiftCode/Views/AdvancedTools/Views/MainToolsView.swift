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

struct MainToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(WorkspaceViewModel.self) private var workspaceViewModel

    @State private var searchQuery = ""
    @State private var selectedCategory = "All"
    @State private var activeToolSheet: ToolbarActionManager.SheetDestination?

    // Static baseline definition of all tools migrated from WorkspaceView, including DocumentationBrowser
    private let allAvailableTools: [WorkspaceHubTool] = [
        WorkspaceHubTool(id: "build_settings", name: "Xcode Build Settings", description: "Manage optimization levels, target SDKs, and build parameters.", iconName: "gearshape.2.fill", colorHex: "#34C759", category: "Build & Deploy", destination: "xcodeBuildSettings"),
        WorkspaceHubTool(id: "build_logs", name: "Xcode Build Logs", description: "Stream compile warnings, errors, and live build output.", iconName: "doc.text.fill", colorHex: "#FF9500", category: "Build & Deploy", destination: "xcodeBuildLogs"),
        WorkspaceHubTool(id: "ipa_builder", name: "IPA Packaging Suite", description: "Pack built iOS apps into IPA containers from SwiftCode without Xcode UI.", iconName: "shippingbox.fill", colorHex: "#AF52DE", category: "Build & Deploy", destination: "ipaBuild"),
        WorkspaceHubTool(id: "dependency_manager", name: "Dependency Manager", description: "Search, import, and manage local or remote Swift packages.", iconName: "puzzlepiece.extension.fill", colorHex: "#007AFF", category: "Utilities", destination: "dependencyManager"),
        WorkspaceHubTool(id: "deployments", name: "Deployments Console", description: "Trigger production deployments to Netlify, Vercel, and GitHub Pages.", iconName: "cloud.fill", colorHex: "#5AC8FA", category: "Build & Deploy", destination: "deployments"),
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Area
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workspace Tools Hub")
                            .font(.title2.bold())
                            .foregroundStyle(.primary)
                        Text("Manage project specifications, build tools, dependency packages, and Git/CI tasks.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.ultraThinMaterial)

                Divider()

                // Filter & Search Controls
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search workspace tools...", text: $searchQuery)
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
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        let categories = ["All", "Build & Deploy", "Git & CI", "Utilities"]
                        ForEach(categories, id: \.self) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                Text(cat)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(selectedCategory == cat ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
                                    .foregroundStyle(selectedCategory == cat ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
                .padding(24)

                Divider()

                // Tools List Grid
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        let filtered = filteredToolsList()

                        if filtered.isEmpty {
                            ContentUnavailableView(
                                "No Tools Found",
                                systemImage: "wrench.and.screwdriver",
                                description: Text("Try adjusting your filters or search query.")
                            )
                            .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                                ForEach(filtered) { tool in
                                    GroupBox {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(spacing: 12) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color(hex: tool.colorHex).opacity(0.12))
                                                        .frame(width: 36, height: 32)
                                                    Image(systemName: tool.iconName)
                                                        .font(.title3)
                                                        .foregroundStyle(Color(hex: tool.colorHex))
                                                }

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(tool.name)
                                                        .font(.subheadline.bold())
                                                        .foregroundStyle(.primary)
                                                    Text(tool.category.uppercased())
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()
                                            }

                                            Text(tool.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)

                                            Button {
                                                launchTool(tool)
                                            } label: {
                                                HStack {
                                                    Text("Open Tool")
                                                    Spacer()
                                                    Image(systemName: "arrow.right.circle.fill")
                                                }
                                                .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                        }
                                        .padding(4)
                                    }
                                    .groupBoxStyle(ModernGroupBoxStyle())
                                }
                            }
                        }
                    }
                    .padding(24)
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 750, minHeight: 500)
            .sheet(item: $activeToolSheet) { destination in
                sheetView(for: destination)
            }
        }
    }

    private func filteredToolsList() -> [WorkspaceHubTool] {
        var list = allAvailableTools
        if !searchQuery.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) || $0.description.localizedCaseInsensitiveContains(searchQuery) }
        }
        if selectedCategory != "All" {
            list = list.filter { $0.category == selectedCategory }
        }
        return list
    }

    private func launchTool(_ tool: WorkspaceHubTool) {
        if let dest = ToolbarActionManager.SheetDestination(rawValue: tool.destination) {
            activeToolSheet = dest
        }
    }

    @ViewBuilder
    private func sheetView(for destination: ToolbarActionManager.SheetDestination) -> some View {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")
        let owner = project.githubRepo?.split(separator: "/").first.map(String.init) ?? ""
        let repo = project.githubRepo?.split(separator: "/").last.map(String.init) ?? ""

        AdaptiveSheet {
            NavigationStack {
                Group {
                    switch destination {
                    case .deployments: DeploymentsView()
                    case .snippetsLibrary: SnippetsLibraryView()
                    case .workspaceProfiles: WorkspaceProfilesView()
                    case .ipaBuild: IPABuildView()
                    case .documentationBrowser: DocumentationBrowserView()
                    case .xcodeBuildSettings: XcodeBuildConfigurationView()
                    case .xcodeBuildLogs: XcodeBuildLogView()
                    case .dependencyManager: DependencyManagerView()
                    case .sourceControl: SourceControlView(gitViewModel: workspaceViewModel.git)
                    case .ciBuild: CIBuildView(project: project)
                    case .simulatorMain: SimulatorMainView()
                    case .personalDocumentation: NSPersonalDocumentationView().frame(minWidth: 800, minHeight: 600)
                    case .devTools: DevToolsMainView()
                    case .collaboration: CollaborationMainView(manager: CollaborationSessionStore.shared.manager(for: project, creatorID: Host.current().localizedName ?? "macOS"))
                    case .sfSymbolsBrowser: SFSymbolPickerView()
                    case .extensionMarketplace: ExtensionMarketplaceView()
                    case .crashLogAnalyzer: CrashLogAnalyzerView()
                    case .projectDependencyGraph: ProjectDependencyGraphView()
                    default:
                        ContentUnavailableView("Detail Pane", systemImage: "hammer")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { activeToolSheet = nil }
                    }
                }
            }
        }
    }
}
