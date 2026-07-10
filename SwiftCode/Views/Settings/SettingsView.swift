import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(\.dismiss) private var dismiss

    @State var viewModel = SettingsViewModel()

    @State private var openRouterKey: String = ""
    @State private var githubToken: String = ""
    @State private var showOpenRouterKey = false
    @State private var showGitHubToken = false
    @State private var keySaved = false
    @State private var tokenSaved = false
    @State private var customModelInput: String = ""
    @State private var customModelSaved = false
    @State private var showExtensions = false
    @State private var cacheCleared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // AI Configuration Group
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("AI Configuration", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("OpenRouter API Key")
                                    .font(.subheadline.bold())
                                HStack {
                                    if showOpenRouterKey {
                                        TextField("sk-or-xxxxxxxxxxxxxxxx", text: $viewModel.openRouterKey)
                                            .textFieldStyle(.roundedBorder)
                                            .autocorrectionDisabled()
                                            .font(.system(.body, design: .monospaced))
                                    } else {
                                        SecureField("sk-or-xxxxxxxxxxxxxxxx", text: $viewModel.openRouterKey)
                                            .textFieldStyle(.roundedBorder)
                                            .autocorrectionDisabled()
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    Button {
                                        showOpenRouterKey.toggle()
                                    } label: {
                                        Image(systemName: showOpenRouterKey ? "eye.slash" : "eye")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    KeychainService.shared.set(viewModel.openRouterKey, forKey: KeychainService.openRouterAPIKey)
                                    Task { await viewModel.saveSettings() }
                                    keySaved = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        keySaved = false
                                    }
                                } label: {
                                    Label(keySaved ? "Saved!" : "Save Key", systemImage: keySaved ? "checkmark.circle.fill" : "key.fill")
                                        .foregroundStyle(keySaved ? .green : .orange)
                                }
                            }

                            Divider().opacity(0.5)

                            Picker("Default Model", selection: $settings.selectedModel) {
                                ForEach(OpenRouterModel.defaults) { model in
                                    Text(model.name).tag(model.id)
                                }
                                if !settings.customModel.isEmpty {
                                    Text("Custom: \(settings.customModel)").tag(settings.customModel)
                                }
                            }
                            .pickerStyle(.menu)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Custom OpenRouter Model ID")
                                    .font(.subheadline.bold())
                                TextField("e.g. mistralai/mistral-7b-instruct", text: $customModelInput)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .font(.system(.body, design: .monospaced))
                                Button {
                                    let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    settings.customModel = trimmed
                                    settings.selectedModel = trimmed
                                    customModelSaved = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        customModelSaved = false
                                    }
                                } label: {
                                    Label(
                                        customModelSaved ? "Saved & Selected!" : "Save & Use Custom Model",
                                        systemImage: customModelSaved ? "checkmark.circle.fill" : "cpu"
                                    )
                                    .foregroundStyle(customModelSaved ? .green : .purple)
                                }
                            }

                            Divider().opacity(0.5)

                            Toggle("Use Custom AI Provider", isOn: $viewModel.useCustomAI)
                            if viewModel.useCustomAI {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Endpoint", text: $viewModel.customAIEndpoint)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("Headers (JSON)", text: $viewModel.customAIHeaders)
                                        .textFieldStyle(.roundedBorder)
                                    SecureField("API Key", text: $viewModel.customAIKey)
                                        .textFieldStyle(.roundedBorder)
                                }
                                .padding(.leading, 12)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    // GitHub Settings Group
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("GitHub Settings", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("GitHub Personal Access Token")
                                    .font(.subheadline.bold())
                                HStack {
                                    if showGitHubToken {
                                        TextField("ghp_xxxxxxxxxxxx", text: $viewModel.githubPAT)
                                            .textFieldStyle(.roundedBorder)
                                            .autocorrectionDisabled()
                                            .font(.system(.body, design: .monospaced))
                                    } else {
                                        SecureField("ghp_xxxxxxxxxxxx", text: $viewModel.githubPAT)
                                            .textFieldStyle(.roundedBorder)
                                            .autocorrectionDisabled()
                                            .font(.system(.body, design: .monospaced))
                                    }
                                    Button {
                                        showGitHubToken.toggle()
                                    } label: {
                                        Image(systemName: showGitHubToken ? "eye.slash" : "eye")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    KeychainService.shared.set(viewModel.githubPAT, forKey: KeychainService.githubToken)
                                    Task { await viewModel.saveSettings() }
                                    tokenSaved = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        tokenSaved = false
                                    }
                                } label: {
                                    Label(tokenSaved ? "Saved!" : "Save Token", systemImage: tokenSaved ? "checkmark.circle.fill" : "key.fill")
                                        .foregroundStyle(tokenSaved ? .green : .blue)
                                }
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    // Editor & File Templates Group
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Editor Settings", systemImage: "doc.text")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            Toggle("Auto Save", isOn: $settings.autoSave)
                            Toggle("Dark Theme", isOn: $settings.useDarkTheme)

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Font Size")
                                    Spacer()
                                    Text("\(Int(settings.editorFontSize))pt")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $settings.editorFontSize, in: 10...24, step: 1)
                                    .tint(.orange)
                            }

                            Divider().opacity(0.5)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Author Name")
                                    .font(.subheadline.bold())
                                TextField("Your Name", text: $settings.fileHeaderAuthor)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Custom Comment")
                                    .font(.subheadline.bold())
                                TextField("Made with SwiftCode", text: $settings.fileHeaderCustomComment)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("File Header Template")
                                    .font(.subheadline.bold())
                                TextEditor(text: $viewModel.headerTemplate)
                                    .frame(height: 80)
                                    .font(.system(.body, design: .monospaced))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                                Text("Tokens: {filename}, {projectname}, {username}, {date}")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    // Theme Customization Group
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Theme Customization", systemImage: "paintbrush")
                                    .font(.headline)
                                    .foregroundColor(.purple)
                                Spacer()
                            }

                            ThemeGalleryView(viewModel: themeVM)
                                .frame(height: 200)
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    // Extensions Group
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Extensions", systemImage: "puzzlepiece.extension")
                                    .font(.headline)
                                    .foregroundColor(.cyan)
                                Spacer()
                            }

                            Button {
                                showExtensions = true
                            } label: {
                                Label("Manage Extensions", systemImage: "puzzlepiece.extension.fill")
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())

                    // Maintenance & Information Group
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("About SwiftCode", systemImage: "info.circle")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()
                            }

                            HStack {
                                Text("Version")
                                Spacer()
                                Text("1.0.0 (Build 1)")
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                viewModel.clearCache()
                                cacheCleared = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    cacheCleared = false
                                }
                            } label: {
                                Label(cacheCleared ? "Caches Cleared!" : "Clear Caches", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }
                    .groupBoxStyle(PreferencesGroupBoxStyle())
                }
                .padding()
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await viewModel.saveSettings() }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showExtensions) {
                ExtensionsView()
            }
            .onAppear {
                viewModel.openRouterKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey) ?? ""
                viewModel.githubPAT = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
                customModelInput = settings.customModel
            }
        }
    }
}

// Custom GroupBox style for better macOS preferences looks
struct PreferencesGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
    }
}
