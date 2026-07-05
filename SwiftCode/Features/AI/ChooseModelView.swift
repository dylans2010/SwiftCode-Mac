import SwiftUI

struct ChooseModelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var selectedProvider: AIProvider = .openRouter
    @State private var apiKey: String = ""
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var lastCheckResult: AgentModelCheckResult? = nil

    private let providerDefaultsKey = "ai.selectedProvider"

    enum AIProvider: String, CaseIterable, Identifiable {
        case openRouter = "OpenRouter"
        case anthropic = "Anthropic"
        case openai = "OpenAI"
        case google = "Gemini"
        case mistral = "Mistral"
        case qwen = "Qwen"
        case offline = "Offline Models"

        var id: String { self.rawValue }

        var keychainKey: String {
            switch self {
            case .openRouter: return KeychainService.openRouterAPIKey
            case .anthropic: return "anthropic_api_key"
            case .openai: return "openai_api_key"
            case .google: return "gemini_api_key"
            case .mistral: return "mistral_api_key"
            case .qwen: return "qwen_api_key"
            case .offline: return "offline_model_selected"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("AI Provider") {
                    Picker("Provider", selection: $selectedProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedProvider) {
                        loadKeyForProvider()
                        availableModels = []
                    }

                    if selectedProvider != .offline {
                        SecureField("API Key", text: $apiKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section {
                    if selectedProvider == .offline {
                        NavigationLink(destination: OfflineModelsView()) {
                            Text("Manage Offline Models")
                        }

                        let installed = OfflineModelManager.shared.installedModels
                        if !installed.isEmpty {
                            Picker("Local Model", selection: $settings.selectedModel) {
                                ForEach(installed) { model in
                                    Text(model.modelName).tag(model.modelName)
                                }
                            }
                        } else {
                            Text("No offline models installed")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            fetchModels()
                        } label: {
                            if isLoadingModels { ProgressView().scaleEffect(0.8) }
                            else { Text("Fetch Available Models") }
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingModels)

                        if !availableModels.isEmpty {
                            Picker("Model", selection: $settings.selectedModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Model Selection")
                }

                Section {
                    Button {
                        testModel()
                    } label: {
                        if isTesting { ProgressView().scaleEffect(0.8) }
                        else { Text("Test Model") }
                    }
                    .disabled(apiKey.isEmpty || settings.selectedModel.isEmpty || isTesting)

                    if let result = testResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result)
                                .font(.caption.bold())
                                .foregroundStyle(result.contains("Success") ? .green : .red)

                            if let check = lastCheckResult {
                                Text("Latency: \(String(format: "%.2f", check.latency))s")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Details: \(check.modelCapability)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Validation")
                }

                if let error = errorMessage {
                    Section("Error Log") {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Choose My Own Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSettings()
                        dismiss()
                    }
                    .disabled(apiKey.isEmpty || settings.selectedModel.isEmpty)
                }
            }
            .onAppear { loadCurrentSettings() }
        }
    }

    private func loadCurrentSettings() {
        if let saved = UserDefaults.standard.string(forKey: providerDefaultsKey),
           let provider = AIProvider(rawValue: saved) {
            selectedProvider = provider
        }
        loadKeyForProvider()
    }

    private func loadKeyForProvider() {
        apiKey = KeychainService.shared.get(forKey: selectedProvider.keychainKey) ?? ""
    }

    private func saveSettings() {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainService.shared.set(trimmedKey, forKey: selectedProvider.keychainKey)
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: providerDefaultsKey)
    }

    private func fetchModels() {
        isLoadingModels = true
        errorMessage = nil

        Task {
            do {
                KeychainService.shared.set(apiKey, forKey: selectedProvider.keychainKey)

                if selectedProvider == .openRouter {
                    let models = try await OpenRouterService.shared.fetchModels()
                    await MainActor.run {
                        availableModels = models.map(\.id)
                        isLoadingModels = false
                    }
                } else {
                    await MainActor.run {
                        availableModels = []
                        errorMessage = "Live model listing is currently supported for OpenRouter. Save your provider key and enter a model ID manually."
                        isLoadingModels = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error fetching models: \(error.localizedDescription)"
                    isLoadingModels = false
                }
            }
        }
    }

    private func testModel() {
        isTesting = true
        testResult = nil
        errorMessage = nil
        lastCheckResult = nil

        Task {
            let result = await AgentModelCheck.shared.checkModel(
                provider: selectedProvider.rawValue,
                apiKey: apiKey,
                model: settings.selectedModel
            )

            await MainActor.run {
                lastCheckResult = result
                isTesting = false

                switch result.status {
                case .success:
                    testResult = "Success: Model verified."
                case .invalid_key:
                    testResult = "Failed: Invalid API Key."
                case .model_not_found:
                    testResult = "Failed: Model not found."
                case .rate_limited:
                    testResult = "Failed: Rate limited."
                case .network_error:
                    testResult = "Failed: Network error."
                case .configuration_error:
                    testResult = "Failed: Configuration mismatch."
                }

                if result.status != .success {
                    errorMessage = result.modelCapability
                }
            }
        }
    }
}
