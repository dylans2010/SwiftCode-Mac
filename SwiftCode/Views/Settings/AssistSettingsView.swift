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

    enum FetchProviderOption: Hashable, Identifiable {
        case openRouter
        case openai
        case anthropic
        case gemini
        case foundation
        case custom(id: UUID, name: String)

        var id: String {
            switch self {
            case .openRouter: return "openRouter"
            case .openai: return "openai"
            case .anthropic: return "anthropic"
            case .gemini: return "gemini"
            case .foundation: return "foundation"
            case .custom(let id, _): return "custom-\(id.uuidString)"
            }
        }

        var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .gemini: return "Gemini"
            case .foundation: return "Foundation Models"
            case .custom(_, let name): return name
            }
        }
    }

    @State private var selectedFetchProvider: FetchProviderOption = .openRouter
    @State private var autoFetchTask: Task<Void, Never>? = nil

    // API Key states
    @State private var openRouterKey = ""
    @State private var openaiKey = ""
    @State private var anthropicKey = ""
    @State private var geminiKey = ""
    @State private var composioKey = ""
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
    @State private var discoveryService = AssistModelDiscoveryService.shared
    @State private var cachedModels: [CachedModel] = []
    @State private var isFetchingAvailableModels = false
    @State private var availableModelsFetchError: String? = nil

    // Sheets Toggles
    @State private var showFreeModelsSheet = false
    @State private var showFoundationModelsSheet = false
    @State private var showMCPServersSheet = false
    @State private var showComposioSheet = false
    @State private var showSkillsSheet = false
    @State private var showAlternativeKeysSheet = false

    // Composio Service Integration
    @State private var composioService = ComposioService.shared

    // Google Account Auth Integration
    @AppStorage("assist_google_auth_mode") private var assistGoogleAuthMode: String = "api_key"
    @ObservedObject private var googleAuth = GoogleAccountAuthService.shared

    // Download Resources State
    @State private var isDownloadingResources = false
    @State private var downloadStatusMessage = "Preparing pip installation..."
    @State private var downloadCompleted = false
    @State private var downloadErrorMessage: String? = nil

    // Fallback rotation reference
    @State private var fallbackRotation = FreeModelsFallback.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 0. Assist System Selection (Native Assist vs Assist on Google Cloud)
                GroupBox {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.2), Color.indigo.opacity(0.3)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "cpu.fill")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Assist System Architecture")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Select the underlying reasoning and tool execution engine")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            // Architecture mode pill badge
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(settings.isGoogleCloudAssist ? Color.blue : Color.purple)
                                    .frame(width: 7, height: 7)
                                Text(settings.isGoogleCloudAssist ? "Google Cloud SDK" : "Native Engine")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(settings.isGoogleCloudAssist ? Color.blue : Color.purple)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background((settings.isGoogleCloudAssist ? Color.blue : Color.purple).opacity(0.1), in: Capsule())
                        }

                        // Modern segmented picker
                        Picker("Active Assist System", selection: $settings.assistSystemID) {
                            Text("Native Assist System")
                                .tag(AppSettings.nativeAssistSystemID)
                            Text("Assist on Google Cloud")
                                .tag(AppSettings.googleCloudAssistSystemID)
                        }
                        .pickerStyle(.segmented)

                        if settings.assistSystemID == AppSettings.googleCloudAssistSystemID {
                            VStack(alignment: .leading, spacing: 16) {
                                // Status banner card
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue.opacity(0.18), Color.cyan.opacity(0.12)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "cloud.rainbow.half")
                                            .symbolRenderingMode(.multicolor)
                                            .font(.system(size: 20))
                                    }

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text("Assist on Google Cloud")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Active Engine")
                                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                                .foregroundStyle(.blue)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.12), in: Capsule())
                                        }

                                        Text("Google Antigravity SDK · Persistent Autonomous Sessions")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    // Dynamic runtime status indicator
                                    googleCloudStatusBadge
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.primary.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                                        )
                                )

                                // Feature pill highlights
                                HStack(spacing: 8) {
                                    Label("Gemini Reasoning", systemImage: "sparkles")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.08), in: Capsule())

                                    Label("Subagent Coordination", systemImage: "person.2.fill")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.indigo)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.indigo.opacity(0.08), in: Capsule())

                                    Label("Background Daemon", systemImage: "bolt.horizontal.fill")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.teal)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.teal.opacity(0.08), in: Capsule())

                                    Spacer()
                                }

                                // Interactive engine controls
                                HStack(spacing: 12) {
                                    Button {
                                        Task {
                                            if GoogleCloudSDKRuntime.shared.isRunning {
                                                await GoogleCloudSDKLifecycleManager.shared.stopEngine()
                                            } else {
                                                try? await GoogleCloudSDKLifecycleManager.shared.startEngine()
                                            }
                                        }
                                    } label: {
                                        Text(GoogleCloudSDKRuntime.shared.isRunning ? "Stop Engine" : "Start Engine")
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(GoogleCloudSDKRuntime.shared.isRunning ? Color.secondary : Color.blue)
                                    .controlSize(.regular)

                                    Button {
                                        Task {
                                            try? await GoogleCloudSDKLifecycleManager.shared.restartEngine()
                                        }
                                    } label: {
                                        Label("Restart Engine", systemImage: "arrow.clockwise")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)

                                    Button {
                                        downloadGoogleAntigravityResources()
                                    } label: {
                                        Label("Download Resources", systemImage: "arrow.down.circle.fill")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.regular)
                                }

                                Text("The Google Cloud engine runs continuously in the background to deliver instant autonomous tool calls, subagent orchestration, and token streaming.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                Divider()
                                    .padding(.vertical, 4)

                                // MARK: - Antigravity Execution Backend Selection
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Antigravity Execution Backend")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Select whether to run Antigravity via the Python Bridge or directly via Downloaded Resources.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(settings.antigravityExecutionMode == "resources" ? Color.green : Color.orange)
                                                .frame(width: 7, height: 7)
                                            Text(settings.antigravityExecutionMode == "resources" ? "Downloaded Resources" : "Python Bridge")
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(settings.antigravityExecutionMode == "resources" ? Color.green : Color.orange)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background((settings.antigravityExecutionMode == "resources" ? Color.green : Color.orange).opacity(0.1), in: Capsule())
                                    }

                                    Picker("Execution Mode", selection: $settings.antigravityExecutionMode) {
                                        Text("Downloaded Resources (Direct Binary)").tag("resources")
                                        Text("Python Bridge Server").tag("bridge")
                                    }
                                    .pickerStyle(.segmented)
                                    .onChange(of: settings.antigravityExecutionMode) { _, _ in
                                        Task {
                                            try? await GoogleCloudSDKLifecycleManager.shared.restartEngine()
                                        }
                                    }

                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: settings.antigravityExecutionMode == "resources" ? "terminal.fill" : "arrow.triangle.pull")
                                            .font(.caption)
                                            .foregroundStyle(settings.antigravityExecutionMode == "resources" ? Color.green : Color.orange)
                                        Text(settings.antigravityExecutionMode == "resources"
                                             ? "Downloaded Resources mode executes the installed google-antigravity binary directly, providing raw SDK performance while retaining token streaming, toolkits, and model selection."
                                             : "Bridge mode runs the Python IPC bridge server to route requests and stream tokens to the UI.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()
                                    .padding(.vertical, 4)

                                // MARK: - Assist Toolkit Configuration
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Assist Toolkit")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Choose whether to use SwiftCode tools or Google Antigravity SDK tools.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        HStack(spacing: 5) {
                                            Circle()
                                                .fill(settings.assistToolkit == "Cloud" ? Color.blue : Color.indigo)
                                                .frame(width: 7, height: 7)
                                            Text(settings.assistToolkit == "Cloud" ? "Cloud (Antigravity)" : "System (SwiftCode)")
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                .foregroundStyle(settings.assistToolkit == "Cloud" ? Color.blue : Color.indigo)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background((settings.assistToolkit == "Cloud" ? Color.blue : Color.indigo).opacity(0.1), in: Capsule())
                                    }

                                    Picker("Assist Toolkit", selection: $settings.assistToolkit) {
                                        Text("System").tag("System")
                                        Text("Cloud").tag("Cloud")
                                    }
                                    .pickerStyle(.segmented)

                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: settings.assistToolkit == "Cloud" ? "cloud.fill" : "macbook.and.iphone")
                                            .font(.caption)
                                            .foregroundStyle(settings.assistToolkit == "Cloud" ? Color.blue : Color.indigo)
                                        Text(settings.assistToolkit == "Cloud"
                                             ? "Cloud toolkit leverages Google Antigravity SDK's built-in file manipulation, command execution, and search tools."
                                             : "System toolkit uses SwiftCode tools (file operations, AST refactoring, builds, testing, and terminal) over the local IPC bridge.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()
                                    .padding(.vertical, 4)

                                // Default Assist Model Configuration
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Default Assist Model")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Choose whether to use the default Antigravity SDK models or choose an App Model from all available endpoints.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Picker("Model Mode", selection: Binding(
                                        get: { settings.useSavedModels ? "App Model" : "Default" },
                                        set: { newMode in
                                            if newMode == "App Model" {
                                                settings.useSavedModels = true
                                                settings.alternativeKeysEnabled = false
                                            } else {
                                                settings.useSavedModels = false
                                            }
                                        }
                                    )) {
                                        Text("Default (Antigravity SDK Models)").tag("Default")
                                        Text("App Model (Choose from Available List)").tag("App Model")
                                    }
                                    .pickerStyle(.segmented)

                                    if settings.useSavedModels {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("Select App Model:")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.secondary)

                                            Picker("App Model Selection", selection: $settings.selectedAssistModelID) {
                                                if discoveryService.discoveredModels.isEmpty {
                                                    Text("Default Model (\(settings.selectedAssistModelID))").tag(settings.selectedAssistModelID)
                                                } else {
                                                    ForEach(discoveryService.discoveredModels) { model in
                                                        Text("\(model.displayName) (\(model.providerName))")
                                                            .tag(model.modelIdentifier)
                                                    }
                                                }
                                            }
                                            .pickerStyle(.menu)
                                        }
                                        .padding(.top, 4)
                                    }
                                }

                                Divider()
                                    .padding(.vertical, 4)

                                Text("Note: 'Use Saved Models' and 'Alternative Keys' are mutually exclusive. Users can only enable one option at a time.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(isOn: Binding(
                                        get: { settings.useSavedModels },
                                        set: { newValue in
                                            settings.useSavedModels = newValue
                                            if newValue {
                                                settings.alternativeKeysEnabled = false
                                            }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Use Saved Models")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Allow Assist to use your saved SwiftCode models instead of relying on Antigravity's default Gemini models.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.switch)

                                    if settings.useSavedModels {
                                        let stats = discoveryService.getDiscoveryStats()
                                        HStack(spacing: 8) {
                                            HStack(spacing: 4) {
                                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                                Text("\(stats.total) models available")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.primary)
                                            }
                                            Text("·").font(.caption2).foregroundStyle(.secondary)
                                            Text("\(stats.providers) providers")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Text("·").font(.caption2).foregroundStyle(.secondary)
                                            Text("\(stats.agentCompatible) agent-compatible")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.blue)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }

                                Divider()
                                    .padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(isOn: Binding(
                                        get: { settings.alternativeKeysEnabled },
                                        set: { newValue in
                                            settings.alternativeKeysEnabled = newValue
                                            if newValue {
                                                settings.useSavedModels = false
                                            }
                                        }
                                    )) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Alternative Keys")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Automatically rotate between saved Gemini API keys when a key encounters rate limits or quota exhaustion.")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.switch)

                                    HStack(spacing: 8) {
                                        let keyCount = AlternativeKeyManager.shared.keys.count
                                        let readyCount = AlternativeKeyManager.shared.keys.filter { $0.isAvailableForUse }.count
                                        HStack(spacing: 4) {
                                            Circle().fill(readyCount > 0 ? Color.green : Color.secondary).frame(width: 6, height: 6)
                                            Text("\(keyCount) Gemini keys saved (\(readyCount) ready)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Button {
                                            showAlternativeKeysSheet = true
                                        } label: {
                                            Label("Manage Keys", systemImage: "key.fill")
                                                .font(.caption2.bold())
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            .padding(.top, 2)
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.purple)
                                    .font(.body)
                                Text("Using the Native Assist System. Standard local compiler loops and multi-provider pipelines are active.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

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

                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Antigravity / Google Authentication")
                                        .font(.caption.bold())
                                    Spacer()
                                    if assistGoogleAuthMode == "api_key" {
                                        Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                                            Label("Get Key", systemImage: "arrow.up.right")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Picker("Google Auth Mode", selection: $assistGoogleAuthMode) {
                                    Text("API Key").tag("api_key")
                                    Text("Sign in to Antigravity").tag("google_oauth")
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .onChange(of: assistGoogleAuthMode) { _, newValue in
                                    AppSettings.shared.assistGoogleAuthMode = newValue
                                }

                                if assistGoogleAuthMode == "google_oauth" {
                                    if googleAuth.isAuthenticated {
                                        // Authenticated state: inline account card/pill
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.headline)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Connected to Antigravity Account")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.primary)

                                                if let email = googleAuth.userEmail, !email.isEmpty {
                                                    Text(email)
                                                        .font(.caption2)
                                                        .foregroundColor(.secondary)
                                                }
                                            }

                                            Spacer()

                                            Button(role: .destructive) {
                                                googleAuth.signOut()
                                            } label: {
                                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                        .padding(10)
                                        .background(Color.green.opacity(0.08))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.green.opacity(0.2), lineWidth: 1)
                                        )
                                    } else {
                                        // Unauthenticated state
                                        VStack(alignment: .leading, spacing: 6) {
                                            Button {
                                                googleAuth.signIn()
                                            } label: {
                                                HStack {
                                                    if googleAuth.isAuthenticating {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                            .padding(.trailing, 4)
                                                        Text("Signing In...")
                                                    } else {
                                                        Image(systemName: "person.badge.key.fill")
                                                        Text("Sign in to Antigravity")
                                                    }
                                                }
                                                .frame(maxWidth: .infinity)
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.regular)
                                            .disabled(googleAuth.isAuthenticating)

                                            Text("Direct quota-free access to Gemini & Vertex AI models without an API key using your Google Account.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            if let error = googleAuth.authError {
                                                HStack(alignment: .top, spacing: 4) {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                        .foregroundColor(.red)
                                                        .font(.caption2)
                                                    Text(error)
                                                        .font(.caption2)
                                                        .foregroundColor(.red)
                                                }
                                                .padding(.top, 2)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                } else {
                                    // API Key Mode
                                    SecureField("Enter Gemini API key", text: $geminiKey)
                                        .textFieldStyle(.roundedBorder)

                                    HStack {
                                        Button {
                                            showAlternativeKeysSheet = true
                                        } label: {
                                            Label("Alternative Keys (\(AlternativeKeyManager.shared.keys.count) configured)", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Spacer()
                                    }
                                    .padding(.top, 2)
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Composio API Key")
                                        .font(.caption.bold())
                                    if composioService.hasConfiguredKey {
                                        HStack(spacing: 4) {
                                            Image(systemName: "lock.shield.fill")
                                                .foregroundColor(.green)
                                                .font(.caption2)
                                            Text("Secured in Keychain")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    Spacer()
                                    Link(destination: URL(string: "https://dashboard.composio.dev/~/project/settings/api-keys")!) {
                                        Label("Get Key", systemImage: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                SecureField(
                                    composioService.hasConfiguredKey ? "•••••••••••••••• (Configured & Protected)" : "ak_... or uak_...",
                                    text: $composioKey
                                )
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

                // 2. Dynamic Available Models Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            HStack(spacing: 8) {
                                Label("Available Models", systemImage: "sparkles")
                                    .font(.headline)
                                    .foregroundColor(.purple)

                                if discoveryService.isDiscovering {
                                    HStack(spacing: 4) {
                                        ProgressView().scaleEffect(0.55)
                                        Text("Refreshing models…")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            let removableProviders = discoveryService.availableProviderNames.filter {
                                $0 != "Apple Foundation Models" && !discoveryService.hiddenProviderNames.contains($0)
                            }
                            if !removableProviders.isEmpty {
                                Menu {
                                    Section("Select Provider to Remove") {
                                        ForEach(removableProviders, id: \.self) { providerName in
                                            Button {
                                                discoveryService.removeProvider(providerName)
                                                Task {
                                                    await discoveryService.discoverAllModels(forceRefresh: true)
                                                }
                                            } label: {
                                                Label("Remove \(providerName)", systemImage: "trash")
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Remove Providers", systemImage: "line.3.horizontal.decrease.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button {
                                Task {
                                    await discoveryService.discoverAllModels(forceRefresh: true)
                                }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(discoveryService.isDiscovering)
                        }

                        let stats = discoveryService.getDiscoveryStats()
                        HStack(spacing: 8) {
                            Text("\(stats.agentCompatible) agent-compatible models")
                                .font(.caption.bold())
                                .foregroundStyle(.primary)
                            Text("·").font(.caption).foregroundStyle(.secondary)
                            Text("\(stats.total) discovered across \(stats.providers) providers")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !discoveryService.hiddenProviderNames.isEmpty {
                                Text("(\(discoveryService.hiddenProviderNames.count) provider(s) removed)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if let last = discoveryService.lastDiscoveryDate {
                                Spacer()
                                Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Compact grouped model browser
                        let groups = discoveryService.modelsByProvider
                        if groups.isEmpty {
                            if discoveryService.isDiscovering {
                                HStack {
                                    ProgressView().scaleEffect(0.7)
                                    Text("Discovering configured models across providers...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 8)
                            } else {
                                Text("No models discovered. Ensure your API keys or custom endpoints are configured.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            }
                        } else {
                            VStack(spacing: 12) {
                                ForEach(groups, id: \.providerName) { group in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(group.providerName)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.primary)

                                            let availCount = group.models.filter { $0.isAvailable }.count
                                            Text("\(availCount) available")
                                                .font(.system(size: 10, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(availCount > 0 ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1), in: Capsule())
                                                .foregroundStyle(availCount > 0 ? Color.green : Color.secondary)

                                            if let err = discoveryService.lastDiscoveryErrors[group.providerName] {
                                                Text("— \(err)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.red)
                                                    .lineLimit(1)
                                            }

                                            Spacer()
                                        }

                                        VStack(spacing: 4) {
                                            ForEach(group.models) { model in
                                                HStack(spacing: 8) {
                                                    // Status indicator dot
                                                    Circle()
                                                        .fill(modelStatusColor(model))
                                                        .frame(width: 6, height: 6)

                                                    // Model name
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        HStack(spacing: 6) {
                                                            Text(model.displayName)
                                                                .font(.system(size: 12, weight: .medium))

                                                            if model.supportsToolCalling {
                                                                Text("Tools")
                                                                    .font(.system(size: 8, weight: .bold))
                                                                    .padding(.horizontal, 4)
                                                                    .padding(.vertical, 1)
                                                                    .background(Color.blue.opacity(0.12))
                                                                    .foregroundStyle(.blue)
                                                                    .cornerRadius(3)
                                                            }

                                                            if model.supportsVision {
                                                                Image(systemName: "eye.fill")
                                                                    .font(.system(size: 8))
                                                                    .foregroundStyle(.secondary)
                                                            }

                                                            if model.supportsSubagents {
                                                                Text("Subagents")
                                                                    .font(.system(size: 8, weight: .bold))
                                                                    .padding(.horizontal, 4)
                                                                    .padding(.vertical, 1)
                                                                    .background(Color.indigo.opacity(0.12))
                                                                    .foregroundStyle(.indigo)
                                                                    .cornerRadius(3)
                                                            }
                                                        }

                                                        Text(model.modelIdentifier)
                                                            .font(.system(size: 10, design: .monospaced))
                                                            .foregroundStyle(.secondary)
                                                    }

                                                    Spacer()

                                                    // Status label
                                                    Text(modelStatusLabel(model))
                                                        .font(.system(size: 10))
                                                        .foregroundStyle(modelStatusColor(model))

                                                    // Selection button
                                                    if settings.selectedAssistModelID == model.modelIdentifier {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.system(size: 14))
                                                            .foregroundStyle(.green)
                                                    } else if model.isAvailable && model.supportsAgenticUse {
                                                        Button("Select") {
                                                            settings.selectedAssistModelID = model.modelIdentifier
                                                            settings.selectedModel = model.modelIdentifier
                                                        }
                                                        .buttonStyle(.bordered)
                                                        .controlSize(.mini)
                                                    }

                                                    // Model Removal / Protection
                                                    if discoveryService.isFoundationModel(model) {
                                                        Image(systemName: "lock.shield")
                                                            .font(.system(size: 11))
                                                            .foregroundStyle(.secondary.opacity(0.6))
                                                            .help("Foundation Models is a system model integration (Protected)")
                                                    } else {
                                                        Button {
                                                            discoveryService.removeModel(model.modelIdentifier)
                                                            Task {
                                                                await discoveryService.discoverAllModels(forceRefresh: true)
                                                            }
                                                        } label: {
                                                            Image(systemName: "trash")
                                                                .font(.system(size: 11))
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        .buttonStyle(.plain)
                                                        .help("Remove model permanently")
                                                    }
                                                }
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(settings.selectedAssistModelID == model.modelIdentifier ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.02))
                                                )
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }

                        Divider().padding(.vertical, 2)

                        // Default Model Picker for quick switching
                        Picker("Active Default Model", selection: $settings.selectedAssistModelID) {
                            ForEach(discoveryService.discoveredModels) { model in
                                Text("\(model.displayName) (\(model.providerName))")
                                    .tag(model.modelIdentifier)
                            }
                        }
                        .pickerStyle(.menu)

                        // Free fallback rotation toggle
                        Toggle(isOn: Binding(
                            get: { fallbackRotation.isEnabled },
                            set: { fallbackRotation.isEnabled = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Automatic Fallback to Other Models")
                                    .font(.subheadline.bold())
                                Text("Rotates through all available models from the active provider automatically if rate limits or network issues strike.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Models for Assist Selection Card
                #if false
                ModelsForAssist(settings: settings, cachedModels: cachedModels, customEndpoints: customEndpointsManager.endpoints)
                #endif

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

                // MCP Server Management Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Model Context Protocol (MCP)", systemImage: "network")
                                .font(.headline)
                                .foregroundColor(.purple)
                            Spacer()
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Connect local stdio sub-processes or remote HTTP services to expand your AI capabilities with custom tools and context schemas.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                showMCPServersSheet = true
                            } label: {
                                Label("Manage MCP Servers", systemImage: "arrow.up.right.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3b. Composio External Integrations Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Composio Tool Integrations", systemImage: "link.badge.plus")
                                .font(.headline)
                                .foregroundColor(.indigo)

                            Spacer()

                            if composioService.isConnected {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 8, height: 8)
                                    Text("Connected")
                                        .font(.caption2.bold())
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.12), in: Capsule())
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Connect external app toolkits (GitHub, Slack, Google Calendar, Jira, Linear) to your Assist agent beyond standard MCP servers.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !composioService.connectedAccounts.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("\(composioService.connectedAccounts.count) Active: \(composioService.connectedAccounts.map { $0.toolkit.capitalized }.joined(separator: ", "))")
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                }
                                .padding(.vertical, 2)
                            }

                            Button {
                                showComposioSheet = true
                            } label: {
                                Label("Manage Composio & Integrations", systemImage: "arrow.up.right.square")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3c. Agent Skills Management Section
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Agent Skills", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundColor(.orange)

                            Spacer()

                            let activeCount = SkillIndex.shared.skills.filter { $0.isEnabled }.count
                            Text("\(activeCount) Active")
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Modular domain-specific engineering playbooks discovered across Codex, Claude, VS Code, and Antigravity. Indexed locally in Application Support.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                showSkillsSheet = true
                            } label: {
                                Label("Manage Agent Skills", systemImage: "arrow.up.right.square")
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
        .sheet(isPresented: $showMCPServersSheet) {
            AddMCPServerView()
        }
        .sheet(isPresented: $showComposioSheet) {
            NavigationStack {
                ScrollView {
                    ComposioSettingsView()
                        .padding()
                }
                .navigationTitle("Composio Integrations")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showComposioSheet = false
                        }
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 650)
        }
        .sheet(isPresented: $showAlternativeKeysSheet) {
            AlternativeKeysView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showSkillsSheet) {
            VStack(spacing: 0) {
                HStack {
                    Label("Agent Skills", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        showSkillsSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))

                Divider()

                ModernSkillsBrowserView()
            }
            .frame(minWidth: 850, minHeight: 600)
        }
        .sheet(isPresented: $isDownloadingResources) {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 64, height: 64)

                    if downloadCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.green)
                    } else if downloadErrorMessage != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.red)
                    } else {
                        ProgressView()
                            .controlSize(.large)
                    }
                }

                VStack(spacing: 6) {
                    Text("Downloading Resources")
                        .font(.system(size: 16, weight: .bold))
                    Text("Installing google-antigravity python package for direct Antigravity SDK execution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .center, spacing: 6) {
                    Text(downloadStatusMessage)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(downloadErrorMessage != nil ? Color.red : (downloadCompleted ? Color.green : Color.blue))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    if let err = downloadErrorMessage {
                        ScrollView {
                            Text(err)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                        .frame(maxHeight: 90)
                        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                if downloadCompleted || downloadErrorMessage != nil {
                    Button("Done") {
                        isDownloadingResources = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
            .padding(28)
            .frame(width: 440)
            .interactiveDismissDisabled(!downloadCompleted && downloadErrorMessage == nil)
        }
        .onAppear {
            loadAPIKeys()
            loadCachedModels()
            Task {
                await discoveryService.discoverAllModels()
            }
        }
        .onChange(of: customEndpoint) { _, _ in
            if isEditingEndpoint && isNewEndpoint { triggerAutoFetchCustomModels() }
        }
        .onChange(of: localEndpointPort) { _, _ in
            if isEditingEndpoint && isNewEndpoint { triggerAutoFetchCustomModels() }
        }
        .onChange(of: customAPIKey) { _, _ in
            if isEditingEndpoint && isNewEndpoint { triggerAutoFetchCustomModels() }
        }
        .onChange(of: isEndpointLocal) { _, _ in
            if isEditingEndpoint && isNewEndpoint { triggerAutoFetchCustomModels() }
        }
    }

    private func loadAPIKeys() {
        openRouterKey = APIKeyManager.shared.retrieveKey(service: .openRouter) ?? ""
        openaiKey = APIKeyManager.shared.retrieveKey(service: .openai) ?? ""
        anthropicKey = APIKeyManager.shared.retrieveKey(service: .anthropic) ?? ""
        geminiKey = APIKeyManager.shared.retrieveKey(service: .google) ?? ""
        composioKey = ""
    }

    private func saveAPIKeys() {
        APIKeyManager.shared.storeKey(service: .openRouter, key: openRouterKey)
        APIKeyManager.shared.storeKey(service: .openai, key: openaiKey)
        APIKeyManager.shared.storeKey(service: .anthropic, key: anthropicKey)
        APIKeyManager.shared.storeKey(service: .google, key: geminiKey)
        let trimmedComposio = composioKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComposio.isEmpty {
            ComposioService.shared.saveApiKey(trimmedComposio)
            composioKey = ""
        }

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

    private func triggerAutoFetchCustomModels() {
        autoFetchTask?.cancel()
        autoFetchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await fetchCustomModels()
        }
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
        triggerAutoFetchCustomModels()
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

        Task {
            await discoveryService.discoverAllModels(forceRefresh: true)
        }
    }

    private func deleteEndpoint(_ endpoint: SavedCustomEndpoint) {
        customEndpointsManager.deleteEndpoint(id: endpoint.id)
        isEditingEndpoint = false
        selectedEndpoint = nil

        Task {
            await discoveryService.discoverAllModels(forceRefresh: true)
        }
    }

    private func loadCachedModels() {
        cachedModels = discoveryService.discoveredModels.map { CachedModel(modelID: $0.modelIdentifier, providerName: $0.providerName) }
    }

    private func saveCachedModels() {
        // No-op to prevent caching models in UserDefaults
    }

    private func modelStatusColor(_ model: AssistAvailableModel) -> Color {
        if model.isCurrentlyRateLimited { return .orange }
        switch model.status {
        case .available:
            return model.supportsAgenticUse ? .green : .purple
        case .authRequired:
            return .yellow
        case .providerUnavailable:
            return .red
        case .unsupportedAgentic:
            return .purple
        case .rateLimited:
            return .orange
        case .configured:
            return .blue
        case .unavailable:
            return .secondary
        }
    }

    private func modelStatusLabel(_ model: AssistAvailableModel) -> String {
        if model.isCurrentlyRateLimited { return "Rate limited" }
        switch model.status {
        case .available:
            return model.supportsAgenticUse ? "Available" : "No tool support"
        case .authRequired:
            return "Auth required"
        case .providerUnavailable:
            return "Provider offline"
        case .unsupportedAgentic:
            return "Unsupported for agentic use"
        case .rateLimited:
            return "Rate limited"
        case .configured:
            return "Configured"
        case .unavailable:
            return "Unavailable"
        }
    }
}

// MARK: - Models For Assist Selection Card

struct ModelsForAssist: View {
    @ObservedObject var settings: AppSettings
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
    private func fetchModels(for option: FetchProviderOption) async {
        isFetchingAvailableModels = true
        availableModelsFetchError = nil
        cachedModels = []

        switch option {
        case .openRouter:
            let trimmed = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                availableModelsFetchError = "OpenRouter API Key is empty."
            } else {
                do {
                    let models = try await LLMService.shared.fetchAvailableModels(provider: .openRouter, key: trimmed)
                    cachedModels = models.map { CachedModel(modelID: $0, providerName: "OpenRouter") }
                } catch {
                    availableModelsFetchError = "OpenRouter fetch failed: \(error.localizedDescription)"
                }
            }
        case .openai:
            let trimmed = openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                availableModelsFetchError = "OpenAI API Key is empty."
            } else {
                do {
                    let models = try await LLMService.shared.fetchAvailableModels(provider: .openai, key: trimmed)
                    cachedModels = models.map { CachedModel(modelID: $0, providerName: "OpenAI") }
                } catch {
                    availableModelsFetchError = "OpenAI fetch failed: \(error.localizedDescription)"
                }
            }
        case .anthropic:
            let trimmed = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                availableModelsFetchError = "Anthropic API Key is empty."
            } else {
                do {
                    let models = try await LLMService.shared.fetchAvailableModels(provider: .anthropic, key: trimmed)
                    cachedModels = models.map { CachedModel(modelID: $0, providerName: "Anthropic") }
                } catch {
                    availableModelsFetchError = "Anthropic fetch failed: \(error.localizedDescription)"
                }
            }
        case .gemini:
            if assistGoogleAuthMode == "google_oauth" {
                if let token = try? await GoogleAccountAuthService.shared.getValidAccessToken() {
                    do {
                        let models = try await LLMService.shared.fetchAvailableModels(provider: .google, key: token)
                        cachedModels = models.map { CachedModel(modelID: $0, providerName: "Gemini") }
                    } catch {
                        availableModelsFetchError = "Gemini fetch failed: \(error.localizedDescription)"
                    }
                } else {
                    availableModelsFetchError = "Please sign in with your Google account first."
                }
            } else {
                let trimmed = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    availableModelsFetchError = "Gemini API Key is empty."
                } else {
                    do {
                        let models = try await LLMService.shared.fetchAvailableModels(provider: .google, key: trimmed)
                        cachedModels = models.map { CachedModel(modelID: $0, providerName: "Gemini") }
                    } catch {
                        availableModelsFetchError = "Gemini fetch failed: \(error.localizedDescription)"
                    }
                }
            }
        case .foundation:
            cachedModels = [
                CachedModel(modelID: AppleFoundationModel.afm3Core.rawValue, providerName: "Foundation Models"),
                CachedModel(modelID: AppleFoundationModel.afm3CoreAdvanced.rawValue, providerName: "Foundation Models")
            ]
        case .custom(let id, let name):
            if let endpoint = customEndpointsManager.endpoints.first(where: { $0.id == id }) {
                do {
                    let models = try await fetchModelsForCustomEndpoint(endpoint)
                    cachedModels = models.map { CachedModel(modelID: $0, providerName: name) }
                } catch {
                    availableModelsFetchError = "Custom endpoint '\(name)' fetch failed: \(error.localizedDescription)"
                }
            } else {
                availableModelsFetchError = "Custom endpoint '\(name)' not found."
            }
        }

        isFetchingAvailableModels = false
    }

    private func fetchModelsForCustomEndpoint(_ endpoint: SavedCustomEndpoint) async throws -> [String] {
        var urlString = ""
        if endpoint.isLocal {
            urlString = "http://localhost:\(endpoint.localPort.trimmingCharacters(in: .whitespacesAndNewlines))/v1/models"
        } else {
            urlString = endpoint.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
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

        if !endpoint.isLocal {
            let trimmedKey = endpoint.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKey.isEmpty {
                request.addValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
            }

            for header in endpoint.headers {
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
            if endpoint.isLocal {
                let fallbackUrlString = "http://localhost:\(endpoint.localPort.trimmingCharacters(in: .whitespacesAndNewlines))/models"
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
        return decoded.data.map { $0.id }
    }

    @ViewBuilder
    private var googleCloudStatusBadge: some View {
        let runtime = GoogleCloudSDKRuntime.shared
        if runtime.isRunning {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Active (v\(runtime.sdkVersion))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.12), in: Capsule())
        } else if runtime.isStarting {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.55)
                Text("Starting Engine...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.12), in: Capsule())
        } else if runtime.isAvailable {
            HStack(spacing: 6) {
                Circle().fill(Color.secondary).frame(width: 8, height: 8)
                Text("Standby (v\(runtime.sdkVersion))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: Capsule())
        } else {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("Unavailable")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.12), in: Capsule())
        }
    }

    private func downloadGoogleAntigravityResources() {
        isDownloadingResources = true
        downloadStatusMessage = "Running pip install google-antigravity..."
        downloadErrorMessage = nil
        downloadCompleted = false

        Task.detached(priority: .userInitiated) {
            let candidatePythons = [
                "/opt/homebrew/bin/python3",
                "/usr/local/bin/python3",
                "/usr/bin/python3"
            ]

            var success = false
            var lastErr = ""

            for pyPath in candidatePythons {
                guard FileManager.default.fileExists(atPath: pyPath) else { continue }

                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: pyPath)
                process.arguments = ["-m", "pip", "install", "google-antigravity", "--upgrade"]
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        success = true
                        await MainActor.run {
                            self.downloadStatusMessage = "google-antigravity installed successfully!"
                            self.downloadCompleted = true
                            self.settings.antigravityExecutionMode = "resources"
                            Task {
                                try? await GoogleCloudSDKLifecycleManager.shared.restartEngine()
                            }
                        }
                        break
                    } else {
                        lastErr = output.isEmpty ? "Process exited with code \(process.terminationStatus)" : output
                    }
                } catch {
                    lastErr = error.localizedDescription
                }
            }

            if !success {
                await MainActor.run {
                    self.downloadErrorMessage = lastErr.isEmpty ? "Failed to locate Python with pip." : lastErr
                    self.downloadStatusMessage = "Installation failed."
                }
            }
        }
    }
}
