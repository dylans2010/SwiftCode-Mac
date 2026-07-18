import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.AssistSettings", category: "AssistSettings")

// MARK: - HeaderItem Helper

struct HeaderItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var key: String
    var value: String
}

// MARK: - CachedModel Struct

struct CachedModel: Codable, Identifiable, Equatable {
    var id: String { modelID }
    let modelID: String
    let providerName: String // "OpenAI", "Anthropic", "Gemini"
}

// MARK: - FreeModelsFallback Configuration Model

@Observable
@MainActor
public final class FreeModelsFallback {
    public static let shared = FreeModelsFallback()

    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "free_models_fallback_enabled")
        }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "free_models_fallback_enabled")
    }

    /// Performs fallback-rotation logic for OpenRouter models containing "free" on their model ID.
    public func executeWithFallback<T>(task: @escaping (String) async throws -> T) async throws -> T {
        let allModels = (try? await OpenRouterClient.shared.fetchModels()) ?? []
        let freeModels = allModels.filter { $0.id.lowercased().contains("free") }

        guard isEnabled && !freeModels.isEmpty else {
            // Default model request execution if toggle is off
            let currentDefaultModel = AppSettings.shared.selectedAssistModelID
            return try await task(currentDefaultModel)
        }

        logger.log("[FreeModelsFallback] fallback-rotation is active. Free models identified: \(freeModels.map { $0.id })")

        var lastError: Error? = nil
        for model in freeModels {
            do {
                logger.log("[FreeModelsFallback] Attempting request utilizing free model: \(model.id)")
                return try await task(model.id)
            } catch {
                logger.error("[FreeModelsFallback] Request failed on model: \(model.id) due to error: \(error.localizedDescription, privacy: .public). Proceeding to next fallback model.")
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
                Task {
                    do {
                        let allModels = try await OpenRouterClient.shared.fetchModels()
                        freeModels = allModels.filter { $0.id.lowercased().contains("free") }
                    } catch {
                        logger.error("[FreeORModels] Failed to fetch free models dynamically: \(error.localizedDescription)")
                    }
                }
            }
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: - FoundationModelsView & FoundationModels Manager Wrapper

@MainActor
struct FoundationModelsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var manager = FoundationModels.shared

    // Diagnostics State
    @State private var isTesting = false
    @State private var testLogs: [String] = []
    @State private var testResponse = ""
    @State private var testSuccess: Bool? = nil
    @State private var lastSuccessTime: String? = {
        UserDefaults.standard.string(forKey: "apple_foundation_model_last_test_time")
    }()
    @State private var failureStage = ""
    @State private var underlyingError = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // GroupBox 1: Overview & Status
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Apple Foundation Models", systemImage: "apple.logo")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Third-Gen Apple Foundation Models")
                                    .font(.headline)
                                Text("Configure on-device intelligence using Apple's native secure architecture (AFM 3).")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // GroupBox 2: Configuration
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Label("Configuration", systemImage: "gearshape")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                Spacer()
                            }

                            Toggle("Enable Private On-Device Models", isOn: $manager.isEnabled)
                                .toggleStyle(.switch)

                            Text("Process natural language commands locally on Apple Silicon.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    if manager.isEnabled {
                        // GroupBox 3: Active Model Select
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Active Model Select (AFM 3 Series)", systemImage: "play.circle")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Spacer()
                                }

                                VStack(spacing: 12) {
                                    ForEach(AppleFoundationModel.allCases) { model in
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack(spacing: 6) {
                                                    Text(model.rawValue)
                                                        .font(.body.bold())

                                                    Text("On-Device")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.green.opacity(0.15))
                                                        .foregroundStyle(.green)
                                                        .cornerRadius(3)
                                                }

                                                Text(model.description)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            if manager.selectedModel == model {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.accentColor)
                                            } else {
                                                Circle()
                                                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                                                    .frame(width: 16, height: 16)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            manager.selectedModel = model
                                        }
                                        .padding(.vertical, 4)

                                        if model != AppleFoundationModel.allCases.last {
                                            Divider()
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())

                        // GroupBox 6: Test Models Diagnostics Console
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Developer Diagnostics Console", systemImage: "terminal.fill")
                                        .font(.headline)
                                        .foregroundColor(.orange)
                                    Spacer()
                                    if let lastTime = lastSuccessTime {
                                        Text("Last Success: \(lastTime)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Text("Perform a real inference generation request using the configured Foundation Model to verify runtime performance, latency, and system readiness.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 12) {
                                    Button(action: runInferenceDiagnostics) {
                                        HStack {
                                            if isTesting {
                                                ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                                            } else {
                                                Image(systemName: "play.terminal.fill")
                                            }
                                            Text(isTesting ? "Testing Model..." : "Test Models")
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .disabled(isTesting)

                                    if testSuccess != nil {
                                        HStack(spacing: 6) {
                                            Image(systemName: testSuccess == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                                .foregroundColor(testSuccess == true ? .green : .red)
                                            Text(testSuccess == true ? "SUCCESS" : "FAILED")
                                                .font(.caption.bold())
                                                .foregroundColor(testSuccess == true ? .green : .red)
                                        }
                                    }
                                }

                                // Logs Terminal
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Diagnostic Run Logs")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)

                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 6) {
                                            if testLogs.isEmpty {
                                                Text("Press 'Test Models' to start diagnostics.")
                                                    .font(.system(.caption, design: .monospaced))
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                ForEach(testLogs, id: \.self) { log in
                                                    Text(log)
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundStyle(log.contains("[Error]") ? .red : (log.contains("[Success]") ? .green : (log.contains("[Warning]") ? .orange : .primary)))
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                }
                                            }
                                        }
                                        .padding(10)
                                    }
                                    .frame(height: 140)
                                    .background(Color.black.opacity(0.12))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                    )
                                }

                                // Live Response Viewer
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Inference Text Response")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)

                                    Text(testResponse.isEmpty ? "No response received yet." : testResponse)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                                        )
                                }

                                if let testSuccess, !testSuccess {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Failure Diagnostics")
                                            .font(.caption.bold())
                                            .foregroundStyle(.red)
                                        Text("Failure Stage: \(failureStage)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Underlying Error: \(underlyingError)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.red.opacity(0.06))
                                    .cornerRadius(6)
                                }
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .navigationTitle("Apple Foundation Models")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 520, height: 680)
    }

    private func runInferenceDiagnostics() {
        guard !isTesting else { return }
        isTesting = true
        testLogs = []
        testResponse = ""
        testSuccess = nil
        failureStage = ""
        underlyingError = ""

        Task {
            let startTime = Date()

            // Stage 1: Initialization
            appendLog("[Info] Initializing Foundation Models...")
            guard FoundationModels.shared.isEnabled else {
                appendLog("[Error] Failed: Foundation Models are disabled in settings.")
                failureStage = "Initialization"
                underlyingError = "Apple Foundation Models are disabled."
                testSuccess = false
                isTesting = false
                return
            }

            // Stage 2: Creating session
            appendLog("[Info] Creating the generation session for \(FoundationModels.shared.selectedModel.rawValue)...")
            try? await Task.sleep(nanoseconds: 100_000_000)

            // Stage 3: Building prompt
            appendLog("[Info] Building prompt: \"Respond with a short sentence confirming that Foundation Models are working.\"")
            let prompt = "Respond with a short sentence confirming that Foundation Models are working."
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Stage 4: Starting generation
            appendLog("[Info] Starting generation...")

            // Stage 5: Receiving streamed output
            appendLog("[Info] Connecting to streaming response generation...")

            var generatedText = ""
            do {
                let streamStartTime = Date()
                try await FoundationModels.shared.streamPrivateResponse(prompt: prompt) { @MainActor token in
                    generatedText += token
                    testResponse = generatedText
                    appendLog("[Streaming] Received token: \"\(token.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                }

                let endTime = Date()
                let totalDuration = endTime.timeIntervalSince(startTime)
                let completionTime = endTime.timeIntervalSince(streamStartTime)

                appendLog("[Success] Response completed successfully.")
                appendLog("[Success] Completion time: \(String(format: "%.3f", completionTime))s")
                appendLog("[Success] Total duration: \(String(format: "%.3f", totalDuration))s")

                testSuccess = true
                let nowStr = Date().formatted(date: .abbreviated, time: .shortened)
                lastSuccessTime = nowStr
                UserDefaults.standard.set(nowStr, forKey: "apple_foundation_model_last_test_time")
            } catch {
                appendLog("[Error] Generation stream failed with error: \(error.localizedDescription)")
                failureStage = "Streaming & Generation"
                underlyingError = error.localizedDescription
                testSuccess = false
            }

            isTesting = false
        }
    }

    private func appendLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        testLogs.append("[\(timestamp)] \(message)")
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
    @State private var openRouterModels: [OpenRouterModel] = []
    @State private var isFetchingOpenRouterModels = false
    @State private var openRouterFetchError: String? = nil

    // Custom Model configurations
    @State private var customEndpointsManager = CustomEndpointManager.shared
    @State private var selectedEndpoint: SavedCustomEndpoint? = nil
    @State private var isEditingEndpoint = false
    @State private var isNewEndpoint = false
    @State private var customEndpointName = ""
    @State private var customEndpoint = "https://api.openai.com/v1"
    @State private var customHeaders: [HeaderItem] = [
        HeaderItem(key: "Content-Type", value: "application/json")
    ]
    @State private var customAPIKey = ""
    @State private var customModels: [String] = []
    @State private var isFetchingCustomModels = false
    @State private var customFetchError: String? = nil
    @State private var isEndpointLocal = false
    @State private var localEndpointPort = "11434"
    @State private var endpointShowInPopup = true

    // Cached Available Models configurations
    @State private var cachedModels: [CachedModel] = []
    @State private var isFetchingAvailableModels = false
    @State private var availableModelsFetchError: String? = nil

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
                                HStack {
                                    Text("OpenRouter API Key")
                                        .font(.caption.bold())
                                    Spacer()
                                    Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                                        Label("Get Key", systemImage: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                SecureField("sk-or-v1-...", text: $openRouterKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("OpenAI API Key")
                                        .font(.caption.bold())
                                    Spacer()
                                    Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                                        Label("Get Key", systemImage: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                SecureField("sk-...", text: $openaiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Anthropic API Key")
                                        .font(.caption.bold())
                                    Spacer()
                                    Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                                        Label("Get Key", systemImage: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                SecureField("sk-ant-...", text: $anthropicKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Gemini (Google) API Key")
                                        .font(.caption.bold())
                                    Spacer()
                                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                                        Label("Get Key", systemImage: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
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

                // 2. Available Models Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Available Models", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Default Model", selection: $settings.selectedAssistModelID) {
                                ForEach(cachedModels) { model in
                                    Text("\(model.modelID) (\(model.providerName))")
                                        .tag(model.modelID)
                                }
                            }
                            .pickerStyle(.menu)

                            HStack(spacing: 12) {
                                Menu {
                                    Button("All Configured APIs") {
                                        Task { await fetchAvailableModels() }
                                    }

                                    Button("OpenAI") {
                                        Task { await fetchAvailableModels(onlyProvider: .openai) }
                                    }
                                    .disabled(openaiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Button("Anthropic") {
                                        Task { await fetchAvailableModels(onlyProvider: .anthropic) }
                                    }
                                    .disabled(anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Button("Gemini") {
                                        Task { await fetchAvailableModels(onlyProvider: .google) }
                                    }
                                    .disabled(geminiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                } label: {
                                    HStack {
                                        if isFetchingAvailableModels {
                                            ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                        }
                                        Text(isFetchingAvailableModels ? "Fetching Models..." : "Fetch Models")
                                    }
                                }
                                .menuStyle(.borderedButton)
                                .disabled(isFetchingAvailableModels)

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

                            if let error = availableModelsFetchError {
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

                // Models for Assist Selection Card
                ModelsForAssist(settings: settings, cachedModels: cachedModels, customEndpoints: customEndpointsManager.endpoints)

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

                // 4. Custom Model Integration Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Custom Model Setup", systemImage: "cube.transparent")
                                .font(.headline)
                                .foregroundColor(.cyan)
                            Spacer()

                            Button(action: openAddEndpoint) {
                                Label("Add Custom", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isEditingEndpoint)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect to any OpenAI-compatible API endpoint (e.g. Together AI, DeepInfra, Ollama, LM Studio, etc.) or local inference port to use custom models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Divider()
                                .padding(.vertical, 4)

                            // 1. Saved Endpoints List
                            if customEndpointsManager.endpoints.isEmpty {
                                Text("No custom endpoints configured. Click 'Add Custom' to register one.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Saved Endpoints")
                                        .font(.subheadline.bold())

                                    ForEach($customEndpointsManager.endpoints) { $endpoint in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Button {
                                                    openEditEndpoint(endpoint)
                                                } label: {
                                                    HStack {
                                                        Text(endpoint.name)
                                                            .font(.headline)
                                                            .foregroundStyle(.blue)
                                                        Text(endpoint.isLocal ? "(Local Port: \(endpoint.localPort))" : "(Remote URL: \(endpoint.endpoint))")
                                                            .font(.caption2)
                                                            .foregroundStyle(.secondary)
                                                    }
                                                }
                                                .buttonStyle(.plain)

                                                if !endpoint.models.isEmpty {
                                                    Text("Models: \(endpoint.models.joined(separator: ", "))")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                } else {
                                                    Text("No models fetched yet")
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            Spacer()

                                            Toggle("Show in Popup", isOn: $endpoint.showInPopup)
                                                .toggleStyle(.switch)
                                                .labelsHidden()
                                                .controlSize(.small)
                                        }
                                        .padding(.vertical, 4)
                                        Divider()
                                    }
                                }
                            }

                            // 2. Editing Form
                            if isEditingEndpoint {
                                Divider()
                                    .padding(.vertical, 8)

                                HStack(spacing: 6) {
                                    Image(systemName: isNewEndpoint ? "plus.circle.fill" : "pencil.circle.fill")
                                        .foregroundStyle(.cyan)
                                    Text(isNewEndpoint ? "New Custom Endpoint" : "Edit Custom Endpoint")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.cyan)
                                }

                                Picker("Type", selection: $isEndpointLocal) {
                                    Label("Remote API", systemImage: "globe").tag(false)
                                    Label("Local Host", systemImage: "laptopcomputer").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .tint(.cyan)

                                VStack(alignment: .leading, spacing: 14) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label("Endpoint Alias Name", systemImage: "tag")
                                            .font(.caption.bold())
                                            .foregroundStyle(.cyan)
                                        TextField("e.g. My Local Llama", text: $customEndpointName)
                                            .textFieldStyle(.roundedBorder)
                                            .autocorrectionDisabled()
                                    }

                                    if isEndpointLocal {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label("Localhost Port", systemImage: "network.badge.shield.half.filled")
                                                .font(.caption.bold())
                                                .foregroundStyle(.cyan)
                                            TextField("11434", text: $localEndpointPort)
                                                .textFieldStyle(.roundedBorder)
                                                .autocorrectionDisabled()
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label("API Endpoint Base URL", systemImage: "link")
                                                .font(.caption.bold())
                                                .foregroundStyle(.cyan)
                                            TextField("https://api.openai.com/v1", text: $customEndpoint)
                                                .textFieldStyle(.roundedBorder)
                                                .autocorrectionDisabled()
                                        }

                                        // KEY-VALUE INTERACTIVE HEADERS FIELDS
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Label("Custom HTTP Headers", systemImage: "list.bullet.rectangle")
                                                    .font(.caption.bold())
                                                    .foregroundStyle(.cyan)
                                                Spacer()
                                                Button(action: {
                                                    customHeaders.append(HeaderItem(key: "New-Header", value: "Value"))
                                                }) {
                                                    Label("Add Header", systemImage: "plus.circle.fill")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.cyan)
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
                                            Label("Custom API Authorization Key", systemImage: "key.fill")
                                                .font(.caption.bold())
                                                .foregroundStyle(.cyan)
                                            SecureField("Enter custom provider API key", text: $customAPIKey)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                    }

                                    Toggle(isOn: $endpointShowInPopup) {
                                        Label("Display on Model Popup Menu", systemImage: "eye.fill")
                                            .font(.caption.bold())
                                            .foregroundStyle(.cyan)
                                    }
                                    .toggleStyle(.switch)
                                    .tint(.cyan)

                                    HStack(spacing: 12) {
                                        Button(action: {
                                            Task { await fetchCustomModels() }
                                        }) {
                                            HStack {
                                                if isFetchingCustomModels {
                                                    ProgressView().scaleEffect(0.6).padding(.trailing, 4)
                                                } else {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                }
                                                Text(isFetchingCustomModels ? "Connecting..." : "Fetch Available Models")
                                                    .fontWeight(.semibold)
                                            }
                                            .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.regular)
                                        .disabled(isFetchingCustomModels)
                                    }
                                    .padding(.top, 4)

                                    if let error = customFetchError {
                                        Text(error)
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }

                                    if !customModels.isEmpty {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Detected Models (\(customModels.count)):")
                                                .font(.subheadline.bold())

                                            ScrollView {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    ForEach(customModels, id: \.self) { m in
                                                        HStack {
                                                            Image(systemName: "cube.fill")
                                                                .foregroundStyle(.blue)
                                                            Text(m)
                                                                .font(.caption.monospaced())
                                                            Spacer()
                                                            Button("Set as Default") {
                                                                settings.selectedAssistModelID = m
                                                            }
                                                            .buttonStyle(.bordered)
                                                            .controlSize(.small)
                                                        }
                                                        .padding(.vertical, 2)
                                                        Divider()
                                                    }
                                                }
                                            }
                                            .frame(maxHeight: 120)
                                        }
                                    }

                                    HStack(spacing: 12) {
                                        Button(action: saveEndpoint) {
                                            Text(isNewEndpoint ? "Save Endpoint" : "Update Endpoint")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.cyan)

                                        if !isNewEndpoint, let endpoint = selectedEndpoint {
                                            Button(role: .destructive) {
                                                deleteEndpoint(endpoint)
                                            } label: {
                                                Text("Delete")
                                            }
                                            .buttonStyle(.bordered)
                                        }

                                        Button("Cancel") {
                                            isEditingEndpoint = false
                                            selectedEndpoint = nil
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(.top, 8)
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
            loadCachedModels()
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

        // Directly store to keychain to ensure instant access across all routing frameworks
        KeychainService.shared.set(openRouterKey, forKey: "openrouter-api-key")
        KeychainService.shared.set(openRouterKey, forKey: KeychainService.openRouterAPIKey)

        hasSavedKeys = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            hasSavedKeys = false
        }

        Task {
            await fetchOpenRouterModels()
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
            var urlString = ""
            if isEndpointLocal {
                urlString = "http://localhost:\(localEndpointPort.trimmingCharacters(in: .whitespacesAndNewlines))/v1/models"
            } else {
                urlString = customEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                if !urlString.lowercased().hasSuffix("/models") {
                    if urlString.hasSuffix("/") {
                        urlString += "models"
                    } else {
                        urlString += "/models"
                    }
                }
            }

            guard let url = URL(string: urlString) else {
                throw NSError(domain: "Invalid URL", code: 0, userInfo: [NSLocalizedDescriptionKey: "The constructed models URL is invalid."])
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0

            if !isEndpointLocal {
                let trimmedKey = customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedKey.isEmpty {
                    request.addValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
                }

                // Construct HTTP request headers
                for header in customHeaders {
                    let trimmedKey = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedVal = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedKey.isEmpty && !trimmedVal.isEmpty {
                        request.addValue(trimmedVal, forHTTPHeaderField: trimmedKey)
                    }
                }
            }

            var data: Data
            var response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                if isEndpointLocal {
                    // Try alternative local path http://localhost:port/models
                    let fallbackUrlString = "http://localhost:\(localEndpointPort.trimmingCharacters(in: .whitespacesAndNewlines))/models"
                    if let fallbackUrl = URL(string: fallbackUrlString) {
                        var fallbackRequest = URLRequest(url: fallbackUrl)
                        fallbackRequest.httpMethod = "GET"
                        fallbackRequest.timeoutInterval = 10.0
                        (data, response) = try await URLSession.shared.data(for: fallbackRequest)
                    } else {
                        throw error
                    }
                } else {
                    throw error
                }
            }

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

    private func openAddEndpoint() {
        isNewEndpoint = true
        customEndpointName = ""
        customEndpoint = "https://api.openai.com/v1"
        customAPIKey = ""
        customHeaders = [HeaderItem(key: "Content-Type", value: "application/json")]
        customModels = []
        isEndpointLocal = false
        localEndpointPort = "11434"
        endpointShowInPopup = true
        selectedEndpoint = nil
        isEditingEndpoint = true
    }

    private func openEditEndpoint(_ endpoint: SavedCustomEndpoint) {
        isNewEndpoint = false
        selectedEndpoint = endpoint
        customEndpointName = endpoint.name
        customEndpoint = endpoint.endpoint
        customAPIKey = endpoint.apiKey
        customHeaders = endpoint.headers
        customModels = endpoint.models
        isEndpointLocal = endpoint.isLocal
        localEndpointPort = endpoint.localPort
        endpointShowInPopup = endpoint.showInPopup
        isEditingEndpoint = true
    }

    private func saveEndpoint() {
        let nameToSave = customEndpointName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Endpoint" : customEndpointName

        let newOrUpdated = SavedCustomEndpoint(
            id: selectedEndpoint?.id ?? UUID(),
            name: nameToSave,
            endpoint: customEndpoint,
            apiKey: customAPIKey,
            headers: customHeaders,
            models: customModels,
            showInPopup: endpointShowInPopup,
            isLocal: isEndpointLocal,
            localPort: localEndpointPort
        )

        if isNewEndpoint {
            customEndpointsManager.endpoints.append(newOrUpdated)
        } else if let selected = selectedEndpoint {
            if let index = customEndpointsManager.endpoints.firstIndex(where: { $0.id == selected.id }) {
                customEndpointsManager.endpoints[index] = newOrUpdated
            }
        }

        isEditingEndpoint = false
        selectedEndpoint = nil
    }

    private func deleteEndpoint(_ endpoint: SavedCustomEndpoint) {
        customEndpointsManager.endpoints.removeAll { $0.id == endpoint.id }
        isEditingEndpoint = false
        selectedEndpoint = nil
    }

    private func loadCachedModels() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.cached_available_models"),
           let decoded = try? JSONDecoder().decode([CachedModel].self, from: data) {
            cachedModels = decoded
        } else {
            // Default presets before first fetch
            cachedModels = [
                CachedModel(modelID: "openai/gpt-4o", providerName: "OpenAI"),
                CachedModel(modelID: "openai/gpt-4o-mini", providerName: "OpenAI"),
                CachedModel(modelID: "anthropic/claude-3.5-sonnet", providerName: "Anthropic"),
                CachedModel(modelID: "google/gemini-2.5-pro", providerName: "Gemini"),
                CachedModel(modelID: "google/gemini-1.5-flash", providerName: "Gemini")
            ]
        }
    }

    private func saveCachedModels() {
        if let data = try? JSONEncoder().encode(cachedModels) {
            UserDefaults.standard.set(data, forKey: "com.swiftcode.cached_available_models")
        }
    }

}

// MARK: - Models For Assist Selection Card

struct ModelsForAssist: View {
    @Bindable var settings: AppSettings
    @State private var filter = AssistModelFilter.shared

    var cachedModels: [CachedModel]
    var customEndpoints: [SavedCustomEndpoint]

    struct AvailableModelItem: Identifiable, Hashable {
        var id: String { modelID }
        let modelID: String
        let name: String
        let category: String
    }

    private var allModels: [AvailableModelItem] {
        var list: [AvailableModelItem] = []

        // 1. Apple Models
        list.append(AvailableModelItem(modelID: AppleFoundationModel.afm3Core.rawValue, name: "Apple AFM 3 Core", category: "Apple Foundation Models"))
        list.append(AvailableModelItem(modelID: AppleFoundationModel.afm3CoreAdvanced.rawValue, name: "Apple AFM 3 Core Advanced", category: "Apple Foundation Models"))

        // 2. HF Local Models
        let localModels = OfflineModelManager.shared.installedModels
        for m in localModels {
            list.append(AvailableModelItem(modelID: m.modelName, name: m.modelName, category: "HuggingFace Local Models"))
        }

        // 3. Custom Endpoint Models
        for endpoint in customEndpoints {
            for m in endpoint.models {
                list.append(AvailableModelItem(modelID: m, name: "\(m) (\(endpoint.name))", category: "Custom Models"))
            }
        }

        // 4. Cloud Models
        for m in cachedModels {
            list.append(AvailableModelItem(modelID: m.modelID, name: "\(m.modelID) (\(m.providerName))", category: "Cloud Models"))
        }

        // Fallback OpenRouter presets if cloud list is empty
        if cachedModels.isEmpty {
            let openRouterPresets = [
                ("openai/gpt-4o", "GPT-4o (OpenRouter)"),
                ("anthropic/claude-3.5-sonnet", "Claude 3.5 Sonnet (OpenRouter)"),
                ("google/gemini-2.5-pro", "Gemini 2.5 Pro (OpenRouter)"),
                ("meta-llama/llama-3-70b-instruct", "Llama 3 70B (OpenRouter)"),
                ("openai/gpt-4o-mini", "GPT-4o Mini (OpenRouter)")
            ]
            for preset in openRouterPresets {
                list.append(AvailableModelItem(modelID: preset.0, name: preset.1, category: "Cloud Models"))
            }
        }

        return list
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Models for Assist", systemImage: "checklist")
                        .font(.headline)
                        .foregroundColor(.indigo)
                    Spacer()
                }

                Text("Select which models should be active and shown in the Assist Workspace or the Agent Model selection. Toggling a model OFF hides it entirely from active popups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let grouped = Dictionary(grouping: allModels, by: { $0.category })

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(grouped.keys.sorted(), id: \.self) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            ForEach(grouped[category] ?? [], id: \.self) { item in
                                Toggle(isOn: Binding(
                                    get: { filter.isEnabled(item.modelID) },
                                    set: { enabled in
                                        filter.toggleModel(item.modelID, enabled: enabled)
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.subheadline.bold())
                                        Text(item.modelID)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.switch)
                                .padding(.vertical, 2)
                            }
                        }

                        if category != grouped.keys.sorted().last {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}

extension AssistSettingsView {
    private func fetchAvailableModels(onlyProvider: LLMProvider? = nil) async {
        isFetchingAvailableModels = true
        availableModelsFetchError = nil

        var fetchedList = cachedModels
        if onlyProvider == nil {
            fetchedList = []
        }

        // 1. Fetch OpenAI
        if onlyProvider == nil || onlyProvider == .openai {
            let trimmedOpenaiKey = openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedOpenaiKey.isEmpty {
                do {
                    let models = try await LLMService.shared.fetchAvailableModels(provider: .openai, key: trimmedOpenaiKey)
                    fetchedList.removeAll { $0.providerName == "OpenAI" }
                    for m in models {
                        fetchedList.append(CachedModel(modelID: m, providerName: "OpenAI"))
                    }
                } catch {
                    logger.warning("[fetchAvailableModels] OpenAI fetch failed: \(error.localizedDescription)")
                }
            }
        }

        // 2. Fetch Anthropic
        if onlyProvider == nil || onlyProvider == .anthropic {
            let trimmedAnthropicKey = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAnthropicKey.isEmpty {
                do {
                    let models = try await LLMService.shared.fetchAvailableModels(provider: .anthropic, key: trimmedAnthropicKey)
                    fetchedList.removeAll { $0.providerName == "Anthropic" }
                    for m in models {
                        fetchedList.append(CachedModel(modelID: m, providerName: "Anthropic"))
                    }
                } catch {
                    logger.warning("[fetchAvailableModels] Anthropic fetch failed: \(error.localizedDescription)")
                }
            }
        }

        // 3. Fetch Gemini
        if onlyProvider == nil || onlyProvider == .google {
            let trimmedGeminiKey = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedGeminiKey.isEmpty {
                do {
                    let models = try await LLMService.shared.fetchAvailableModels(provider: .google, key: trimmedGeminiKey)
                    fetchedList.removeAll { $0.providerName == "Gemini" }
                    for m in models {
                        fetchedList.append(CachedModel(modelID: m, providerName: "Gemini"))
                    }
                } catch {
                    logger.warning("[fetchAvailableModels] Gemini fetch failed: \(error.localizedDescription)")
                }
            }
        }

        if fetchedList.isEmpty {
            availableModelsFetchError = "Failed to fetch models from any configured provider. Please ensure your API keys are correct and active."
        } else {
            // Delete cached models and cache the new results
            cachedModels = fetchedList
            saveCachedModels()
        }

        isFetchingAvailableModels = false
    }
}
