import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPane: SettingsPane = .general
    @State private var searchQuery = ""

    enum SettingsPane: String, CaseIterable, Identifiable {
        case general = "General"
        case aiAssist = "AI & Assist"
        case offlineModels = "Offline Models"
        case templates = "Project Templates"
        case plugins = "Plugin Manager"
        case themes = "Themes"
        case extensions = "Extensions"
        case updates = "Updates"
        case credits = "Credits"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .aiAssist: return "sparkles"
            case .offlineModels: return "externaldrive.fill"
            case .templates: return "doc.badge.plus"
            case .plugins: return "cpu"
            case .themes: return "paintbrush.fill"
            case .extensions: return "puzzlepiece.extension.fill"
            case .updates: return "arrow.triangle.2.circlepath.circle.fill"
            case .credits: return "person.2.fill"
            }
        }
    }

    var filteredPanes: [SettingsPane] {
        if searchQuery.isEmpty {
            return SettingsPane.allCases
        } else {
            return SettingsPane.allCases.filter {
                $0.rawValue.lowercased().contains(searchQuery.lowercased())
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Settings Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search preferences...", text: $searchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .padding()

                Divider()

                List(filteredPanes, selection: $selectedPane) { pane in
                    NavigationLink(value: pane) {
                        Label(pane.rawValue, systemImage: pane.icon)
                            .font(.headline)
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Preferences")
            .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
        } detail: {
            VStack(spacing: 0) {
                // Toolbar Header
                HStack {
                    Text(selectedPane.rawValue)
                        .font(.title2.bold())
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider()

                ScrollView {
                    paneView(for: selectedPane)
                        .padding(24)
                        .frame(maxWidth: 800, alignment: .leading)
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .frame(width: 1050, height: 750)
        .onAppear {
            // Restore previous selection state
            if let savedValue = UserDefaults.standard.string(forKey: "com.swiftcode.settings.selectedPane"),
               let restored = SettingsPane(rawValue: savedValue) {
                selectedPane = restored
            }
        }
        .onChange(of: selectedPane) { _, newValue in
            // Save state for restoration
            UserDefaults.standard.set(newValue.rawValue, forKey: "com.swiftcode.settings.selectedPane")
        }
    }

    @ViewBuilder
    private func paneView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsView()
                .environmentObject(settings)
        case .aiAssist:
            AssistSettingsView()
        case .offlineModels:
            OfflineModelsView()
        case .templates:
            ProjectTemplateView()
        case .plugins:
            PluginManagerView()
        case .themes:
            ThemeManagementView()
                .environmentObject(settings)
        case .extensions:
            ExtensionsView()
        case .updates:
            UpdatesView()
        case .credits:
            CreditsView()
        }
    }
}
