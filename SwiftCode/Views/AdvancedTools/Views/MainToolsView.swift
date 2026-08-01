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

// MARK: - Sidebar Selection

private enum ToolsSidebarSelection: Hashable {
    case all
    case category(String)
}

public struct MainToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""
    @State private var selectedSection: ToolsSidebarSelection = .all

    // User Customization States
    @State private var hiddenTools: Set<String> = []
    @State private var hiddenCategories: Set<String> = []
    @State private var categoryOrder: [String] = []

    // Sheet Presentation States
    @State private var showingCustomizer = false
    @State private var showingHiddenToolsSheet = false

    public init() {}

    private let cardMinWidth: CGFloat = 232
    private let gridSpacing: CGFloat = 14
    private let contentPadding: CGFloat = 20

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
        WorkspaceHubTool(id: "visual_ui_builder", name: "Visual UI Builder", description: "Build modern Apple user interfaces visually for SwiftUI, AppKit, UIKit, visionOS, WidgetKit, and watchOS.", iconName: "paintpalette.fill", colorHex: "#FF2D55", category: "Utilities", destination: "visualUIBuilder"),
        WorkspaceHubTool(id: "dev_tools", name: "Developer Utility Bundle", description: "JSON formatters, base64 encoders, regex checkers, and JWT tools.", iconName: "wrench.and.screwdriver.fill", colorHex: "#FF3B30", category: "Utilities", destination: "devTools"),
        WorkspaceHubTool(id: "collaboration", name: "Live Collaboration", description: "Coordinate real-time coding sessions with team members.", iconName: "person.2.fill", colorHex: "#34C759", category: "Utilities", destination: "collaboration"),
        WorkspaceHubTool(id: "sf_symbols", name: "SF Symbols Browser", description: "Search and copy native SF Symbol identifiers.", iconName: "sparkles", colorHex: "#FFCC00", category: "Utilities", destination: "sfSymbolsBrowser"),
        WorkspaceHubTool(id: "extension_marketplace", name: "Extension Marketplace", description: "Browse and install community tools, themes, and extensions.", iconName: "bag.fill", colorHex: "#AF52DE", category: "Utilities", destination: "extensionMarketplace"),
        WorkspaceHubTool(id: "crash_log_analyzer", name: "Crash Log Analyzer", description: "Analyze production crash logs and trace symbolic memory leaks.", iconName: "doc.richtext.fill", colorHex: "#FF3B30", category: "Utilities", destination: "crashLogAnalyzer"),
        WorkspaceHubTool(id: "project_dependency_graph", name: "Project Dependency Graph", description: "Render internal project file import mapping and graphs.", iconName: "network", colorHex: "#007AFF", category: "Utilities", destination: "projectDependencyGraph"),
        WorkspaceHubTool(id: "workspace_profiles", name: "Workspace Profiles", description: "Create, edit, duplicate, and switch between workspace setting profiles.", iconName: "person.crop.square.fill.and.at.rectangle.fill", colorHex: "#34C759", category: "Utilities", destination: "workspaceProfiles"),
        WorkspaceHubTool(id: "snippets_library", name: "Snippets Library", description: "Store, tag, categorize, and quickly insert code snippet templates.", iconName: "curlybraces", colorHex: "#FF9500", category: "Utilities", destination: "snippetsLibrary"),
        WorkspaceHubTool(id: "documentation_browser", name: "Documentation Browser", description: "Full featured windowed multi-pane documentation browser and visual reference workspace.", iconName: "doc.text.magnifyingglass", colorHex: "#007AFF", category: "Utilities", destination: "documentationBrowser"),
        WorkspaceHubTool(id: "search_documentation", name: "Search Documentation", description: "Search project documentation, DocSymbols, project notes, API documentation, and other indexed resources.", iconName: "magnifyingglass", colorHex: "#AF52DE", category: "Utilities", destination: "searchDocumentation"),
        WorkspaceHubTool(id: "database_explorer", name: "Database Explorer", description: "Visually design, manage, connect, inspect, query, generate, and synchronize databases.", iconName: "cylinder.split.1x2.fill", colorHex: "#34C759", category: "Utilities", destination: "databaseExplorer"),
        WorkspaceHubTool(id: "project_inspector", name: "Project Inspector", description: "Recursive directory scanner, live modules analysis, and AI layer refactoring reviews.", iconName: "square.text.square", colorHex: "#FF9500", category: "Utilities", destination: "projectInspector"),
        WorkspaceHubTool(id: "localization_manager", name: "Localization Manager", description: "Multi-pane string catalogs and .xcstrings editor with layout previews & validation checks.", iconName: "text.book.closed.fill", colorHex: "#007AFF", category: "Utilities", destination: "localizationManager"),
        WorkspaceHubTool(id: "licenses_add", name: "Licenses", description: "Quickly add open source license templates directly to your project codebase.", iconName: "doc.text.fill", colorHex: "#FF9500", category: "Utilities", destination: "licensesAdd")
    ]

    private var filteredCategories: [String] {
        categoryOrder.filter { !hiddenCategories.contains($0) }
    }

    private var visibleTools: [WorkspaceHubTool] {
        allAvailableTools.filter { !hiddenTools.contains($0.id) && filteredCategories.contains($0.category) }
    }

    private var scopedTools: [WorkspaceHubTool] {
        switch selectedSection {
        case .all:
            return visibleTools
        case .category(let category):
            return visibleTools.filter { $0.category == category }
        }
    }

    private var searchResults: [WorkspaceHubTool] {
        guard !searchQuery.isEmpty else { return scopedTools }
        return scopedTools.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.description.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var detailTitle: String {
        switch selectedSection {
        case .all: return "All Tools"
        case .category(let category): return category
        }
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                Divider()
                content
            }
            .navigationTitle("Tools")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingHiddenToolsSheet = true
                    } label: {
                        Label("Hidden Tools", systemImage: "eye.slash")
                    }
                    .help("View and restore hidden tools")

                    Button {
                        showingCustomizer = true
                    } label: {
                        Label("Customize", systemImage: "slider.horizontal.3")
                    }
                    .help("Reorder sections and manage tool visibility")
                }
            }
        }
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search tools")
        .onAppear { loadSettings() }
        .onChange(of: filteredCategories) { _, updated in
            if case .category(let category) = selectedSection, !updated.contains(category) {
                selectedSection = .all
            }
        }
        .sheet(isPresented: $showingCustomizer) {
            LayoutCustomizerView(
                allAvailableTools: allAvailableTools,
                hiddenTools: $hiddenTools,
                hiddenCategories: $hiddenCategories,
                categoryOrder: $categoryOrder,
                onSave: { saveSettings() }
            )
        }
        .sheet(isPresented: $showingHiddenToolsSheet) {
            HiddenToolsView(
                allAvailableTools: allAvailableTools,
                hiddenTools: $hiddenTools,
                onRestore: { saveSettings() },
                onLaunch: { tool in
                    showingHiddenToolsSheet = false
                    launchTool(tool)
                }
            )
        }
        .frame(minWidth: 560, minHeight: 620)
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        Picker("", selection: $selectedSection) {
            Label("All", systemImage: "square.grid.2x2.fill")
                .tag(ToolsSidebarSelection.all)

            ForEach(filteredCategories, id: \.self) { category in
                Label(category, systemImage: iconForCategory(category))
                    .tag(ToolsSidebarSelection.category(category))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, contentPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        Group {
            if searchResults.isEmpty {
                if !searchQuery.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else if visibleTools.isEmpty {
                    ContentUnavailableView(
                        "No Tools Available",
                        systemImage: "square.dashed",
                        description: Text("Unhide sections or tools from Customize Layout to see them here.")
                    )
                } else {
                    ContentUnavailableView(
                        "Nothing Here Yet",
                        systemImage: "tray",
                        description: Text("This section has no visible tools.")
                    )
                }
            } else {
                GeometryReader { proxy in
                    let availableWidth = proxy.size.width - (contentPadding * 2)
                    let columnCount = max(1, Int((availableWidth + gridSpacing) / (cardMinWidth + gridSpacing)))
                    let columns = Array(
                        repeating: GridItem(.flexible(), spacing: gridSpacing, alignment: .top),
                        count: columnCount
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(detailTitle)
                                    .font(.title3.weight(.semibold))
                                Spacer()
                                Text("\(searchResults.count) tool\(searchResults.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                                ForEach(searchResults) { tool in
                                    ToolGridCard(
                                        tool: tool,
                                        onOpen: { launchTool(tool) },
                                        onHide: {
                                            hiddenTools.insert(tool.id)
                                            saveSettings()
                                        }
                                    )
                                }
                            }
                        }
                        .padding(contentPadding)
                    }
                    .clipped()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
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

    // MARK: - User Settings Manager

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let ht = defaults.stringArray(forKey: "com.swiftcode.assist.hiddenTools") {
            hiddenTools = Set(ht)
        }
        if let hc = defaults.stringArray(forKey: "com.swiftcode.assist.hiddenCategories") {
            hiddenCategories = Set(hc)
        }
        if let co = defaults.stringArray(forKey: "com.swiftcode.assist.toolsCategoryOrder") {
            let existingCats = Set(allAvailableTools.map { $0.category })
            categoryOrder = co.filter { existingCats.contains($0) }
            for cat in existingCats where !categoryOrder.contains(cat) {
                categoryOrder.append(cat)
            }
        } else {
            categoryOrder = Array(Set(allAvailableTools.map { $0.category })).sorted()
        }
    }

    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(Array(hiddenTools), forKey: "com.swiftcode.assist.hiddenTools")
        defaults.set(Array(hiddenCategories), forKey: "com.swiftcode.assist.hiddenCategories")
        defaults.set(categoryOrder, forKey: "com.swiftcode.assist.toolsCategoryOrder")
    }
}

// MARK: - Tool Grid Card

private struct ToolGridCard: View {
    let tool: WorkspaceHubTool
    let onOpen: () -> Void
    let onHide: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 24, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color(hex: tool.colorHex))
                        .frame(width: 32, height: 32)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .opacity(isHovering ? 1 : 0)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(tool.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(height: 132, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isHovering ? Color(hex: tool.colorHex).opacity(0.4) : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .shadow(color: .black.opacity(isHovering ? 0.10 : 0.03), radius: isHovering ? 8 : 2, y: isHovering ? 4 : 1)
        .scaleEffect(isHovering ? 1.015 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Open Tool", systemImage: "arrow.up.forward.app") { onOpen() }
            Divider()
            Button("Hide Tool", systemImage: "eye.slash", role: .destructive) { onHide() }
        }
        .help(tool.description)
    }
}

// MARK: - Layout Customizer View

struct LayoutCustomizerView: View {
    let allAvailableTools: [WorkspaceHubTool]
    @Binding var hiddenTools: Set<String>
    @Binding var hiddenCategories: Set<String>
    @Binding var categoryOrder: [String]
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categoryOrder, id: \.self) { category in
                        Toggle(isOn: Binding(
                            get: { !hiddenCategories.contains(category) },
                            set: { isVisible in
                                if isVisible {
                                    hiddenCategories.remove(category)
                                } else {
                                    hiddenCategories.insert(category)
                                }
                            }
                        )) {
                            Text(category)
                                .font(.body.weight(.medium))
                        }
                        .toggleStyle(.checkbox)
                    }
                    .onMove { indices, newOffset in
                        categoryOrder.move(fromOffsets: indices, toOffset: newOffset)
                    }
                } header: {
                    Text("Sections")
                } footer: {
                    Text("Drag rows to reorder sections. Uncheck to hide a section from the Tools Hub.")
                }

                ForEach(categoryOrder, id: \.self) { category in
                    let tools = allAvailableTools.filter { $0.category == category }
                    Section(category) {
                        ForEach(tools) { tool in
                            Toggle(isOn: Binding(
                                get: { !hiddenTools.contains(tool.id) },
                                set: { isVisible in
                                    if isVisible {
                                        hiddenTools.remove(tool.id)
                                    } else {
                                        hiddenTools.insert(tool.id)
                                    }
                                }
                            )) {
                                Label {
                                    Text(tool.name)
                                } icon: {
                                    Image(systemName: tool.iconName)
                                        .foregroundStyle(Color(hex: tool.colorHex))
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .navigationTitle("Customize Tools Layout")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 520, height: 640)
    }
}

// MARK: - Hidden Tools View

struct HiddenToolsView: View {
    let allAvailableTools: [WorkspaceHubTool]
    @Binding var hiddenTools: Set<String>
    let onRestore: () -> Void
    let onLaunch: (WorkspaceHubTool) -> Void

    @Environment(\.dismiss) private var dismiss

    private var hiddenToolsList: [WorkspaceHubTool] {
        allAvailableTools.filter { hiddenTools.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if hiddenToolsList.isEmpty {
                    ContentUnavailableView(
                        "No Hidden Tools",
                        systemImage: "checkmark.seal",
                        description: Text("Every tool is currently visible in the Tools Hub.")
                    )
                } else {
                    List {
                        ForEach(hiddenToolsList) { tool in
                            HStack(spacing: 12) {
                                Image(systemName: tool.iconName)
                                    .font(.title3)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color(hex: tool.colorHex))
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(tool.name)
                                        .font(.subheadline.weight(.semibold))
                                    Text(tool.category)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Open") {
                                    onLaunch(tool)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    hiddenTools.remove(tool.id)
                                    onRestore()
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button("Restore Tool", systemImage: "arrow.uturn.backward") {
                                    hiddenTools.remove(tool.id)
                                    onRestore()
                                }
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
            .navigationTitle("Hidden Tools")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: 520)
    }
}
