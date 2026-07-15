import SwiftUI

@MainActor
struct AssistSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    // API Key states
    @State private var openRouterKey = ""
    @State private var openaiKey = ""
    @State private var anthropicKey = ""
    @State private var geminiKey = ""
    @State private var hasSavedKeys = false

    // OpenRouter models state
    @State private var openRouterModels: [OpenRouterModel] = OpenRouterModel.defaults
    @State private var isFetchingOpenRouterModels = false
    @State private var openRouterFetchError: String? = nil

    // Custom Model configurations
    @State private var customEndpoint = "https://api.openai.com/v1"
    @State private var customHeaders = "{\n  \"Content-Type\": \"application/json\"\n}"
    @State private var customAPIKey = ""
    @State private var customModels: [String] = []
    @State private var isFetchingCustomModels = false
    @State private var customFetchError: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. API Keys Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("AI Provider API Keys", systemImage: "key.fill")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Configure API Keys to power your smart developer assistance models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("OpenRouter API Key")
                                    .font(.caption.bold())
                                SecureField("sk-or-v1-...", text: $openRouterKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("OpenAI API Key")
                                    .font(.caption.bold())
                                SecureField("sk-...", text: $openaiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Anthropic API Key")
                                    .font(.caption.bold())
                                SecureField("sk-ant-...", text: $anthropicKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Gemini (Google) API Key")
                                    .font(.caption.bold())
                                SecureField("Enter Gemini API key", text: $geminiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: saveAPIKeys) {
                                Label("Save API Keys", systemImage: "checkmark.circle.fill")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .padding(.top, 10)

                            if hasSavedKeys {
                                Text("API Keys saved securely in the system keychain!")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. OpenRouter Selection Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("OpenRouter Model Selection", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Default OpenRouter Model", selection: $settings.selectedAssistModelID) {
                                ForEach(openRouterModels) { model in
                                    Text("\(model.name) (\(model.id))")
                                        .tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)

                            Button(action: {
                                Task { await fetchOpenRouterModels() }
                            }) {
                                HStack {
                                    if isFetchingOpenRouterModels {
                                        ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(isFetchingOpenRouterModels ? "Fetching OpenRouter Models..." : "Fetch Available Models")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isFetchingOpenRouterModels)

                            if let error = openRouterFetchError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Text("Select the primary model used for AI assistance and code generation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3. Custom Model Integration Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Custom Model Setup", systemImage: "cube.transparent")
                                .font(.headline)
                                .foregroundColor(.cyan)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect to any OpenAI-compatible API endpoint (e.g. Together AI, DeepInfra, Ollama, LM Studio, etc.) to list and use custom models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()
                                .padding(.vertical, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("API Endpoint URL")
                                    .font(.caption.bold())
                                TextField("https://api.openai.com/v1", text: $customEndpoint)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Custom Headers (JSON formatted)")
                                    .font(.caption.bold())
                                TextEditor(text: $customHeaders)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(height: 100)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Custom API Key")
                                    .font(.caption.bold())
                                SecureField("Enter custom provider API key", text: $customAPIKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: {
                                Task { await fetchCustomModels() }
                            }) {
                                HStack {
                                    if isFetchingCustomModels {
                                        ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                                    } else {
                                        Image(systemName: "play.fill")
                                    }
                                    Text(isFetchingCustomModels ? "Connecting..." : "Fetch Custom Models")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isFetchingCustomModels)

                            if let error = customFetchError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            if !customModels.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Available Models:")
                                        .font(.subheadline.bold())
                                        .padding(.top, 8)

                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            ForEach(customModels, id: \.self) { model in
                                                HStack {
                                                    Image(systemName: "cube.fill")
                                                        .foregroundStyle(.blue)
                                                    Text(model)
                                                        .font(.caption.monospaced())
                                                    Spacer()
                                                    Button("Set as Default") {
                                                        settings.selectedAssistModelID = model
                                                    }
                                                    .buttonStyle(.bordered)
                                                    .controlSize(.small)
                                                }
                                                .padding(.vertical, 4)
                                                Divider()
                                            }
                                        }
                                    }
                                    .frame(maxHeight: 200)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 4. About Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("About Assist", systemImage: "info.circle")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        Text("Assist allows you to use AI to help you write code, explain concepts, and perform complex refactorings.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Assist Settings")
        .onAppear {
            loadAPIKeys()
            Task {
                await fetchOpenRouterModels()
            }
        }
    }

    private func loadAPIKeys() {
        openRouterKey = APIKeyManager.shared.retrieveKey(service: .openRouter) ?? ""
        openaiKey = APIKeyManager.shared.retrieveKey(service: .openai) ?? ""
        anthropicKey = APIKeyManager.shared.retrieveKey(service: .anthropic) ?? ""
        geminiKey = APIKeyManager.shared.retrieveKey(service: .google) ?? ""
    }

    private func saveAPIKeys() {
        APIKeyManager.shared.storeKey(service: .openRouter, key: openRouterKey)
        APIKeyManager.shared.storeKey(service: .openai, key: openaiKey)
        APIKeyManager.shared.storeKey(service: .anthropic, key: anthropicKey)
        APIKeyManager.shared.storeKey(service: .google, key: geminiKey)

        hasSavedKeys = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            hasSavedKeys = false
        }
    }

    private func fetchOpenRouterModels() async {
        isFetchingOpenRouterModels = true
        openRouterFetchError = nil
        do {
            let models = try await OpenRouterClient.shared.fetchModels()
            if !models.isEmpty {
                openRouterModels = models
            }
        } catch {
            openRouterFetchError = error.localizedDescription
        }
        isFetchingOpenRouterModels = false
    }

    private func fetchCustomModels() async {
        isFetchingCustomModels = true
        customFetchError = nil
        customModels = []

        do {
            var urlString = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let _ = URL(string: urlString) else {
                throw NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "The custom endpoint URL is invalid."])
            }

            if !urlString.lowercased().hasSuffix("/models") {
                if urlString.hasSuffix("/") {
                    urlString += "models"
                } else {
                    urlString += "/models"
                }
            }

            guard let url = URL(string: urlString) else {
                throw NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to construct the models endpoint URL."])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            let trimmedKey = customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                request.addValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            }

            let trimmedHeaders = customHeaders.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedHeaders.isEmpty, let data = trimmedHeaders.data(using: .utf8) {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (key, value) in json {
                        request.addValue("\(value)", forHTTPHeaderField: key)
                    }
                }
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = String(data: data, encoding: .utf8) ?? "No body"
                throw NSError(domain: "API Error", code: code, userInfo: [NSLocalizedDescriptionKey: "Server returned status \(code): \(body)"])
            }

            struct CustomModelsResponse: Codable {
                let data: [ModelEntry]
                struct ModelEntry: Codable {
                    let id: String
                }
            }

            let decoded = try JSONDecoder().decode(CustomModelsResponse.self, from: data)
            let modelsList = decoded.data.map { $0.id }
            if modelsList.isEmpty {
                customFetchError = "No models were found in the response."
            } else {
                customModels = modelsList
            }
        } catch {
            customFetchError = error.localizedDescription
        }

        isFetchingCustomModels = false
    }
}
