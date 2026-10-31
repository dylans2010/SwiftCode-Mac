import SwiftUI

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

    private var allAvailableTools: [WorkspaceHubTool] {
        SwiftCodeToolbarDelegate.allAvailableTools
    }

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
        .background(VisualEffectView(material: .sidebar, blendingMode: .withinWindow))
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Build & Deploy": return "hammer.fill"
        case "Git & CI": return "arrow.triangle.branch"
        case "Utilities": return "wrench.and.screwdriver.fill"
        case "Search & Navigation": return "magnifyingglass"
        default: return "gearshape.fill"
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Build & Deploy": return .orange
        case "Git & CI": return .green
        case "Utilities": return .blue
        case "Search & Navigation": return .purple
        default: return .indigo
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
            .liquidGlass(style: .standard, cornerRadius: 12)
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
