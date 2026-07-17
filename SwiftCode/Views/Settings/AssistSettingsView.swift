import SwiftUI
import os

private let logger = Logger(subsystem: "com.swiftcode.AssistSettings", category: "AssistSettings")

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
                                Text("Configure on-device and server-side intelligence using Apple's native secure architecture (AFM 3).")
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

                            Text("Process natural language commands locally on Apple Silicon and route complex sessions through Private Cloud Compute.")
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

                        // GroupBox 4: Reasoning Level
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("Reasoning Level", systemImage: "brain.head.profile")
                                        .font(.headline)
                                        .foregroundColor(.purple)
                                    Spacer()
                                }

                                Picker("Reasoning Effort", selection: $manager.reasoningLevel) {
                                    ForEach(AppReasoningLevel.allCases) { level in
                                        Text(level.rawValue.capitalized).tag(level)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Text(manager.reasoningLevel.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
            appendLog("[Info] Starting generation with reasoning level: \(FoundationModels.shared.reasoningLevel.rawValue)...")

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

                // 4. Custom Model Integration Section
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

                            // KEY-VALUE INTERACTIVE HEADERS FIELDS
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

        // Directly store to keychain to ensure instant access across all routing frameworks
        KeychainService.shared.set(openRouterKey, forKey: "openrouter-api-key")

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

            // Construct HTTP request headers
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
