import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(\.dismiss) private var dismiss

    @SceneStorage("com.swiftcode.settings.selectedPane") private var selectedPaneRaw: String = SettingsPane.general.rawValue
    @State private var searchText = ""

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

    var selectedPane: SettingsPane {
        SettingsPane(rawValue: selectedPaneRaw) ?? .general
    }

    var filteredPanes: [SettingsPane] {
        if searchText.isEmpty {
            return SettingsPane.allCases
        } else {
            return SettingsPane.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Search bar for Preferences
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search settings...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding()

                List(filteredPanes, selection: Binding(
                    get: { selectedPane },
                    set: { selectedPaneRaw = $0.rawValue }
                )) { pane in
                    NavigationLink(value: pane) {
                        Label(pane.rawValue, systemImage: pane.icon)
                            .font(.headline)
                    }
                    .accessibilityLabel("\(pane.rawValue) Preferences Pane")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Preferences")
            .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    paneView(for: selectedPane)
                        .padding(24)
                        .transition(.opacity)
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
