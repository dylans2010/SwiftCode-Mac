import SwiftUI

struct SettingsView: View {
    @State var viewModel = SettingsViewModel()
    @Environment(ThemeViewModel.self) var themeVM

    var body: some View {
        TabView {
            Form {
                Section("AI Provider") {
                    SecureField("OpenRouter API Key", text: $viewModel.openRouterKey)

                    if !viewModel.availableModels.isEmpty {
                        Picker("Default Model", selection: $viewModel.selectedModel) {
                            ForEach(viewModel.availableModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    } else {
                        Button("Fetch Models") {
                            Task { await viewModel.fetchAvailableModels() }
                        }
                    }

                    Toggle("Use Custom AI Provider", isOn: $viewModel.useCustomAI)
                    if viewModel.useCustomAI {
                        TextField("Endpoint", text: $viewModel.customAIEndpoint)
                        TextField("Headers (JSON)", text: $viewModel.customAIHeaders)
                        SecureField("API Key", text: $viewModel.customAIKey)
                    }
                }

                Section("GitHub") {
                    SecureField("GitHub PAT", text: $viewModel.githubPAT)
                }

                Button("Save Settings") {
                    Task { await viewModel.saveSettings() }
                }
            }
            .tabItem { Label("Accounts & AI", systemImage: "person.crop.circle") }
            .padding()

            Form {
                Section("Appearance") {
                    ThemeGalleryView()
                        .frame(height: 200)
                }

                Section("Editor") {
                    Button("Customize Theme") {
                        // Open theme editor
                    }
                }
            }
            .tabItem { Label("Personalization", systemImage: "paintbrush") }
            .padding()

            Form {
                Section("Maintenance") {
                    Button("Clear Caches") {
                        viewModel.clearCache()
                    }
                    .foregroundStyle(.red)
                }

                Section("App Information") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tabItem { Label("Advanced", systemImage: "cpu") }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
}
