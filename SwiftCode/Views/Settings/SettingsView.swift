import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPane: SettingsPane = .general

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

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                NavigationLink(value: pane) {
                    Label(pane.rawValue, systemImage: pane.icon)
                        .font(.headline)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Preferences")
            .frame(minWidth: 200)
        } detail: {
            VStack(spacing: 0) {
                ScrollView {
                    paneView(for: selectedPane)
                        .padding()
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
        .frame(width: 850, height: 600)
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
