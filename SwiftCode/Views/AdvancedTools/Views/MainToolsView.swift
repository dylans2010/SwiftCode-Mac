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

    // User Customization States
    @State private var hiddenTools: Set<String> = []
    @State private var hiddenCategories: Set<String> = []
    @State private var categoryOrder: [String] = []

    // Sheet Presentation States
    @State private var showingCustomizer = false
    @State private var showingHiddenToolsSheet = false

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
        categoryOrder.filter { !hiddenCategories.contains($0) }
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

                    if filteredCategories.isEmpty || allToolsHiddenAndFiltered() {
                        VStack(spacing: 12) {
                            Image(systemName: "square.dashed")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No active tools are visible.")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                            Text("Try adjusting your custom layout or unhiding categories/tools.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 40)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Workspace Tools Hub")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingHiddenToolsSheet = true
                    } label: {
                        Label("Hidden Tools", systemImage: "eye.slash.fill")
                    }
                    .help("View and launch hidden tools")

                    Button {
                        showingCustomizer = true
                    } label: {
                        Label("Customize Layout", systemImage: "slider.horizontal.3")
                    }
                    .help("Configure sections, ordering, and tool visibility")
                }
            }
            .onAppear {
                loadSettings()
            }
            .sheet(isPresented: $showingCustomizer) {
                LayoutCustomizerView(
                    allAvailableTools: allAvailableTools,
                    hiddenTools: $hiddenTools,
                    hiddenCategories: $hiddenCategories,
                    categoryOrder: $categoryOrder,
                    onSave: {
                        saveSettings()
                    }
                )
            }
            .sheet(isPresented: $showingHiddenToolsSheet) {
                HiddenToolsView(
                    allAvailableTools: allAvailableTools,
                    hiddenTools: $hiddenTools,
                    onRestore: {
                        saveSettings()
                    },
                    onLaunch: { tool in
                        showingHiddenToolsSheet = false
                        launchTool(tool)
                    }
                )
            }
        }
    }

    private func toolsForCategory(_ category: String) -> [WorkspaceHubTool] {
        let categoryList = allAvailableTools.filter { $0.category == category && !hiddenTools.contains($0.id) }
        if searchQuery.isEmpty {
            return categoryList
        } else {
            return categoryList.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                $0.description.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    private func allToolsHiddenAndFiltered() -> Bool {
        for category in filteredCategories {
            if !toolsForCategory(category).isEmpty {
                return false
            }
        }
        return true
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
            for cat in existingCats {
                if !categoryOrder.contains(cat) {
                    categoryOrder.append(cat)
                }
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
            ScrollView {
                VStack(spacing: 24) {
                    // Category configuration card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Sections Reordering & Visibility", systemImage: "list.bullet.indent")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            Text("Arrange the order in which sections are displayed in the Tools Hub and choose which sections to show or hide.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            VStack(spacing: 12) {
                                ForEach(Array(categoryOrder.enumerated()), id: \.offset) { index, category in
                                    HStack(spacing: 12) {
                                        Toggle("", isOn: Binding(
                                            get: { !hiddenCategories.contains(category) },
                                            set: { isVisible in
                                                if isVisible {
                                                    hiddenCategories.remove(category)
                                                } else {
                                                    hiddenCategories.insert(category)
                                                }
                                            }
                                        ))
                                        .toggleStyle(.checkbox)

                                        Text(category)
                                            .font(.subheadline.bold())

                                        Spacer()

                                        // Reordering control buttons
                                        HStack(spacing: 4) {
                                            Button {
                                                moveCategory(from: index, to: index - 1)
                                            } label: {
                                                Image(systemName: "chevron.up")
                                            }
                                            .disabled(index == 0)
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button {
                                                moveCategory(from: index, to: index + 1)
                                            } label: {
                                                Image(systemName: "chevron.down")
                                            }
                                            .disabled(index == categoryOrder.count - 1)
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(.vertical, 4)

                                    if index != categoryOrder.count - 1 {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Individual Tools configuration card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Individual Tool Visibility", systemImage: "wrench.and.screwdriver")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            Text("Toggle visibility for individual tools within active sections.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()

                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(categoryOrder, id: \.self) { category in
                                    let tools = allAvailableTools.filter { $0.category == category }
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(category)
                                            .font(.caption.bold())
                                            .foregroundStyle(.secondary)

                                        ForEach(tools) { tool in
                                            HStack(spacing: 12) {
                                                Toggle("", isOn: Binding(
                                                    get: { !hiddenTools.contains(tool.id) },
                                                    set: { isVisible in
                                                        if isVisible {
                                                            hiddenTools.remove(tool.id)
                                                        } else {
                                                            hiddenTools.insert(tool.id)
                                                        }
                                                    }
                                                ))
                                                .toggleStyle(.checkbox)

                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(Color(hex: tool.colorHex).opacity(0.12))
                                                        .frame(width: 28, height: 24)
                                                    Image(systemName: tool.iconName)
                                                        .font(.caption)
                                                        .foregroundStyle(Color(hex: tool.colorHex))
                                                }

                                                Text(tool.name)
                                                    .font(.subheadline)

                                                Spacer()
                                            }
                                        }
                                    }
                                    .padding(.bottom, 6)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
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
        .frame(width: 500, height: 600)
    }

    private func moveCategory(from: Int, to: Int) {
        guard to >= 0 && to < categoryOrder.count else { return }
        categoryOrder.swapAt(from, to)
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
            ScrollView {
                VStack(spacing: 24) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Hidden Tools Archive", systemImage: "eye.slash")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                            }

                            if hiddenToolsList.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "checkmark.seal")
                                        .font(.system(size: 32))
                                        .foregroundStyle(.green)
                                    Text("No tools are currently hidden")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                            } else {
                                VStack(spacing: 16) {
                                    ForEach(hiddenToolsList) { tool in
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
                                                Text(tool.category)
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            HStack(spacing: 8) {
                                                Button("Restore") {
                                                    hiddenTools.remove(tool.id)
                                                    onRestore()
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.regular)

                                                Button("Open") {
                                                    onLaunch(tool)
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .controlSize(.regular)
                                            }
                                        }

                                        if tool != hiddenToolsList.last {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Hidden Tools Workspace")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 480, height: 500)
    }
}
