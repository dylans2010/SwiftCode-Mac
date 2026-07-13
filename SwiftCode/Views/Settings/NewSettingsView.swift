import SwiftUI

struct SettingsItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    let iconBgColor: Color
    let category: String
    let sortOrder: Int
    let keywords: String
    let destination: AnyView

    // For Sendable conformance of AnyView
    init(id: String, title: String, icon: String, iconBgColor: Color, category: String, sortOrder: Int, keywords: String, destination: AnyView) {
        self.id = id
        self.title = title
        self.icon = icon
        self.iconBgColor = iconBgColor
        self.category = category
        self.sortOrder = sortOrder
        self.keywords = keywords
        self.destination = destination
    }
}

struct NewSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(\.dismiss) private var dismiss

    @SceneStorage("com.swiftcode.newsettings.selectedPane") private var selectedPaneId: String = "general"
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    // Centralized Settings Registry
    private var registry: [SettingsItem] {
        [
            SettingsItem(
                id: "general",
                title: "General",
                icon: "gearshape.fill",
                iconBgColor: .gray,
                category: "System",
                sortOrder: 10,
                keywords: "general interface background appearance font behavior launch startup log path executable editor",
                destination: AnyView(GeneralSettingsView().environmentObject(settings))
            ),
            SettingsItem(
                id: "ai_assist",
                title: "AI & Assist",
                icon: "sparkles",
                iconBgColor: .purple,
                category: "A.I. & Tools",
                sortOrder: 20,
                keywords: "ai assist smart complete chat model code suggestion intelligence openrouter local key API suggestions",
                destination: AnyView(AssistSettingsView())
            ),
            SettingsItem(
                id: "offline_models",
                title: "Offline Models",
                icon: "externaldrive.fill",
                iconBgColor: .blue,
                category: "A.I. & Tools",
                sortOrder: 30,
                keywords: "offline models local coreml download storage model weight install local model manager",
                destination: AnyView(OfflineModelsView())
            ),
            SettingsItem(
                id: "templates",
                title: "Project Templates",
                icon: "doc.badge.plus",
                iconBgColor: .teal,
                category: "A.I. & Tools",
                sortOrder: 40,
                keywords: "templates project custom scaffold boilerplates ios app macos framework library structure boilerplate",
                destination: AnyView(ProjectTemplateView())
            ),
            SettingsItem(
                id: "plugins",
                title: "Plugin Manager",
                icon: "cpu",
                iconBgColor: .orange,
                category: "A.I. & Tools",
                sortOrder: 50,
                keywords: "plugins custom tools automate script capability action plugin manifest code manager interop",
                destination: AnyView(PluginManagerView())
            ),
            SettingsItem(
                id: "themes",
                title: "Themes",
                icon: "paintbrush.fill",
                iconBgColor: .pink,
                category: "System",
                sortOrder: 15,
                keywords: "themes colors styles customization dark light visual custom editor fonts highlight darkpro nord gruvbox",
                destination: AnyView(ThemeManagementView().environmentObject(settings))
            ),
            SettingsItem(
                id: "extensions",
                title: "Extensions",
                icon: "puzzlepiece.extension.fill",
                iconBgColor: .indigo,
                category: "Extension & Updates",
                sortOrder: 60,
                keywords: "extensions language linter formatter kotlin python rust typescript spm formatter linting tools capability market",
                destination: AnyView(ExtensionsView())
            ),
            SettingsItem(
                id: "updates",
                title: "Updates",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                iconBgColor: .green,
                category: "Extension & Updates",
                sortOrder: 70,
                keywords: "updates version release check upgrade changelog download system latest news improvements bugfix",
                destination: AnyView(UpdatesView())
            ),
            SettingsItem(
                id: "credits",
                title: "Credits",
                icon: "person.2.fill",
                iconBgColor: .cyan,
                category: "About",
                sortOrder: 80,
                keywords: "credits licenses developers thirdparty apple swift library contributors team community about",
                destination: AnyView(CreditsView())
            )
        ]
    }

    private var categories: [String] {
        ["System", "A.I. & Tools", "Extension & Updates", "About"]
    }

    private var filteredItems: [SettingsItem] {
        if searchText.isEmpty {
            return registry
        } else {
            return registry.filter { item in
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.category.localizedCaseInsensitiveContains(searchText) ||
                item.keywords.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var selectedItem: SettingsItem {
        registry.first { $0.id == selectedPaneId } ?? registry[0]
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // macOS System Settings search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search settings...", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.vertical, 14)

                List(selection: Binding(
                    get: { selectedPaneId },
                    set: { selectedPaneId = $0 ?? "general" }
                )) {
                    ForEach(categories, id: \.self) { category in
                        let itemsInCategory = filteredItems.filter { $0.category == category }
                            .sorted { $0.sortOrder < $1.sortOrder }

                        if !itemsInCategory.isEmpty {
                            Section(header: Text(category.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)) {
                                    ForEach(itemsInCategory) { item in
                                        NavigationLink(value: item.id) {
                                            HStack(spacing: 12) {
                                                // Colored SF Symbol background icon
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                        .fill(item.iconBgColor)
                                                        .frame(width: 24, height: 24)
                                                    Image(systemName: item.icon)
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundColor(.white)
                                                }

                                                Text(item.title)
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(.primary)

                                                Spacer()
                                            }
                                            .padding(.vertical, 2)
                                        }
                                        .accessibilityLabel("\(item.title) Preferences Pane")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 240)
            .navigationTitle("Preferences")
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header with Icon & Title
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedItem.iconBgColor)
                                    .frame(width: 38, height: 38)
                                Image(systemName: selectedItem.icon)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedItem.title)
                                    .font(.title2.bold())
                                Text(selectedItem.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                        Divider()
                            .padding(.horizontal, 24)

                        selectedItem.destination
                            .padding(24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 1050, height: 750)
        .keyboardShortcut(.cancelAction) // support keyboard esc or cancel
    }
}
