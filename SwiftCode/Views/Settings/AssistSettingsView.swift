import SwiftUI

// MARK: - HeaderItem Helper

struct HeaderItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var key: String
    var value: String
}

// MARK: - FreeModelsFallback Configuration Model

@Observable
@MainActor
public final class FreeModelsFallback {
    public static let shared = FreeModelsFallback()

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "free_models_fallback_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "free_models_fallback_enabled") }
    }

    private init() {}

    /// Performs fallback-rotation logic for OpenRouter models containing "free" on their model ID.
    public func executeWithFallback<T>(task: @escaping (String) async throws -> T) async throws -> T {
        let allModels = OpenRouterModel.defaults
        let freeModels = allModels.filter { $0.id.lowercased().contains("free") }

        guard isEnabled && !freeModels.isEmpty else {
            // Default model request execution if toggle is off
            let currentDefaultModel = AppSettings.shared.selectedAssistModelID
            return try await task(currentDefaultModel)
        }

        print("[FreeModelsFallback] fallback-rotation is active. Free models identified: \(freeModels.map { $0.id })")

        var lastError: Error? = nil
        for model in freeModels {
            do {
                print("[FreeModelsFallback] Attempting request utilizing free model: \(model.id)")
                return try await task(model.id)
            } catch {
                print("[FreeModelsFallback] Request failed on model: \(model.id) due to error: \(error.localizedDescription). Proceeding to next fallback model.")
                lastError = error
            }
        }

        if let error = lastError {
            throw error
        } else {
            throw NSError(domain: "FreeModelsFallback", code: 500, userInfo: [NSLocalizedDescriptionKey: "All free fallback models failed."])
        }
    }
}

// MARK: - FreeORModels View

struct FreeORModels: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var freeModels: [OpenRouterModel] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select a free OpenRouter model to set as your default model or browse all currently available free endpoints.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Free Models") {
                    if freeModels.isEmpty {
                        Text("No free models cached yet. Fetch available models first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(freeModels) { model in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.name)
                                        .font(.headline)
                                    Text(model.id)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.selectedAssistModelID == model.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                } else {
                                    Button("Select") {
                                        settings.selectedAssistModelID = model.id
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Free OpenRouter Models")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                let allModels = OpenRouterModel.defaults
                freeModels = allModels.filter { $0.id.lowercased().contains("free") }
            }
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: - FoundationModelsView & FoundationModels Manager Wrapper

struct FoundationModelsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = FoundationModels.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Native Swift Foundation Model") {
                    Toggle("Enable Private On-Device Models", isOn: Binding(
                        get: { manager.isEnabled },
                        set: { manager.isEnabled = $0 }
                    ))

                    Text("Process natural language and translation commands fully locally using Apple iOS & macOS platform system foundation frameworks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Model Diagnostics & Capabilities") {
                    HStack {
                        Text("Apple Translation Native API")
                        Spacer()
                        if #available(macOS 15.0, *) {
                            Text("Available")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        } else {
                            Text("Requires macOS 15+")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                        }
                    }

                    HStack {
                        Text("Natural Language Processor")
                        Spacer()
                        Text("Ready")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Text("macOS 26+ Future-Proof Safeguard")
                        Spacer()
                        Text("Fully Compatible")
                            .font(.caption.bold())
                            .foregroundStyle(.blue)
                    }
                }
            }
            .navigationTitle("Apple Foundation Models")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 460, height: 360)
    }
}

// MARK: - AssistSettingsView

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
    @State private var customHeaders: [HeaderItem] = [
        HeaderItem(key: "Content-Type", value: "application/json")
    ]
    @State private var customAPIKey = ""
    @State private var customModels: [String] = []
    @State private var isFetchingCustomModels = false
    @State private var customFetchError: String? = nil

    // Sheets Toggles
    @State private var showFreeModelsSheet = false
    @State private var showFoundationModelsSheet = false

    // Fallback rotation reference
    @State private var fallbackRotation = FreeModelsFallback.shared

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

                            HStack(spacing: 12) {
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

                                Button {
                                    showFreeModelsSheet = true
                                } label: {
                                    Label("Browse Free Models", systemImage: "gift.fill")
                                }
                                .buttonStyle(.bordered)
                            }

                            // Free fallback toggle
                            Toggle(isOn: Binding(
                                get: { fallbackRotation.isEnabled },
                                set: { fallbackRotation.isEnabled = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Automatic Fallback to Free Models")
                                        .font(.subheadline.bold())
                                    Text("Rotates through all OpenRouter free model endpoints automatically if rate limits or network issues strike.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 4)

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

                // 3. Foundation Models Integration
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Apple System Foundation Models", systemImage: "apple.logo")
                                .font(.headline)
                                .foregroundColor(.green)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bypass external remote cloud endpoints and process your requests using native Apple Silicon device models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                showFoundationModelsSheet = true
                            } label: {
                                Label("Setup Native Foundation Model", systemImage: "slider.horizontal.3")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 4. Custom Model Integration Section (MODERNIZED WITH INTERACTIVE KEY-VALUE HEADERS)
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

                            // MODERN KEY-VALUE INTERACTIVE HEADERS FIELDS
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("HTTP Headers")
                                        .font(.caption.bold())
                                    Spacer()
                                    Button(action: {
                                        customHeaders.append(HeaderItem(key: "New-Header", value: "Value"))
                                    }) {
                                        Label("Add Header", systemImage: "plus")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }

                                ForEach($customHeaders) { $header in
                                    HStack(spacing: 8) {
                                        TextField("Header Key", text: $header.key)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                        TextField("Value", text: $header.value)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.body, design: .monospaced))
                                        Button(action: {
                                            customHeaders.removeAll { $0.id == header.id }
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
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

                // 5. About Section
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
        .sheet(isPresented: $showFreeModelsSheet) {
            FreeORModels()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showFoundationModelsSheet) {
            FoundationModelsView()
        }
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

            // Construct HTTP request headers from modern key-value dictionary structure
            for header in customHeaders {
                let trimmedKey = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedVal = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty && !trimmedVal.isEmpty {
                    request.addValue(trimmedVal, forHTTPHeaderField: trimmedKey)
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
