import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var openRouterKey: String = ""
    @State private var githubToken: String = ""
    @State private var showOpenRouterKey = false
    @State private var showGitHubToken = false
    @State private var keySaved = false
    @State private var tokenSaved = false
    @State private var customModelInput: String = ""
    @State private var customModelSaved = false
    @State private var showExtensions = false

    var body: some View {
        NavigationStack {
            Form {
                // AI Settings
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OpenRouter API Key")
                                .font(.headline)
                            if openRouterKey.isEmpty {
                                Text("Not Set")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text("••••••••\(String(openRouterKey.suffix(4)))")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        Button {
                            showOpenRouterKey.toggle()
                        } label: {
                            Image(systemName: showOpenRouterKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if showOpenRouterKey {
                        TextField("sk-or-xxxxxxxxxxxxxxxx", text: $openRouterKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            KeychainService.shared.set(openRouterKey, forKey: KeychainService.openRouterAPIKey)
                            keySaved = true
                            showOpenRouterKey = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                keySaved = false
                            }
                        } label: {
                            Label(keySaved ? "Saved!" : "Save Key", systemImage: keySaved ? "checkmark.circle.fill" : "key.fill")
                                .foregroundStyle(keySaved ? .green : .orange)
                        }
                    }

                    Picker("Default Model", selection: $settings.selectedModel) {
                        ForEach(OpenRouterModel.defaults) { model in
                            Text(model.name).tag(model.id)
                        }
                        if !settings.customModel.isEmpty {
                            Text("Custom: \(settings.customModel)").tag(settings.customModel)
                        }
                    }

                    // Custom model entry
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom OpenRouter Model")
                                    .font(.headline)
                                Text("Enter any valid OpenRouter model ID")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        TextField("e.g. mistralai/mistral-7b-instruct", text: $customModelInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                        Button {
                            let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            settings.customModel   = trimmed
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
                } header: {
                    Label("AI Configuration", systemImage: "sparkles")
                }

                // GitHub Settings
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GitHub Personal Access Token")
                                .font(.headline)
                            if githubToken.isEmpty {
                                Text("Not Set")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else {
                                Text("••••••••\(String(githubToken.suffix(4)))")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        Button {
                            showGitHubToken.toggle()
                        } label: {
                            Image(systemName: showGitHubToken ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if showGitHubToken {
                        TextField("ghp_xxxxxxxxxxxx", text: $githubToken)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))

                        Button {
                            KeychainService.shared.set(githubToken, forKey: KeychainService.githubToken)
                            tokenSaved = true
                            showGitHubToken = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                tokenSaved = false
                            }
                        } label: {
                            Label(tokenSaved ? "Saved!" : "Save Token", systemImage: tokenSaved ? "checkmark.circle.fill" : "key.fill")
                                .foregroundStyle(tokenSaved ? .green : .blue)
                        }
                    }
                } header: {
                    Label("GitHub", systemImage: "arrow.triangle.2.circlepath")
                }

                // Editor Settings
                Section {
                    Toggle("Auto Save", isOn: $settings.autoSave)

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

                    Toggle("Dark Theme", isOn: $settings.useDarkTheme)
                } header: {
                    Label("Editor", systemImage: "doc.text")
                }

                // File Template Settings
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Author Name")
                            .font(.headline)
                        Text("Used in the // Created by header of new Swift files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Your Name", text: $settings.fileHeaderAuthor)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Comment")
                            .font(.headline)
                        Text("Added as a second header comment in new Swift files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TextField("Made with SwiftCode", text: $settings.fileHeaderCustomComment)
                        .autocorrectionDisabled()
                } header: {
                    Label("File Templates", systemImage: "doc.badge.plus")
                } footer: {
                    Text("New .swift files will include:\n// Created by <Author> on <Date>.\n// <Custom Comment>")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://openrouter.ai")!) {
                        Label("OpenRouter API", systemImage: "link")
                    }
                    Link(destination: URL(string: "https://docs.github.com/en/rest")!) {
                        Label("GitHub API Docs", systemImage: "link")
                    }
                } header: {
                    Label("About SwiftCode", systemImage: "info.circle")
                }

                // Extensions
                Section {
                    Button {
                        showExtensions = true
                    } label: {
                        Label("Manage Extensions", systemImage: "puzzlepiece.extension.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Label("Extensions", systemImage: "puzzlepiece.extension")
                } footer: {
                    Text("Install, enable, disable, or create custom extensions for SwiftCode.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showExtensions) {
                ExtensionsView()
            }
            .onAppear {
                openRouterKey  = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey) ?? ""
                githubToken    = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
                customModelInput = settings.customModel
            }
        }
    }
}
