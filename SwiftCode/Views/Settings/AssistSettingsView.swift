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
    // Google OAuth client secret input (stored in Keychain on save; the
    // field itself never displays a saved secret).
    @State private var googleClientSecretInput = ""
    // OAuth client ID override input (persisted via AppSettings).
    @State private var googleOAuthClientIDInput = ""
    // Disclosure expansion state.
    @State private var isAPIKeysExpanded = false
    // Terminal Command Approvals opens as a sheet: AssistSettingsView isn't
    // hosted in a NavigationStack, so a NavigationLink would never navigate.
    @State private var showingTerminalCommands = false
    @State private var isAdvancedExpanded = false
    // SwiftCode Cloud discovered models.
    @State private var cloudModels: [SCCloudModelInfo] = []
    @State private var cloudModelsUpdatedAt: Date? = nil
    @State private var isRefreshingCloudModels = false

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

    // Google Account Auth Integration & Antigravity Quota
    // Account authentication ("Sign in with Google") is the default mode;
    // API-key mode is an explicit opt-in alternative.
    @AppStorage("assist_google_auth_mode") private var assistGoogleAuthMode: String = "google_oauth"
    @ObservedObject private var googleAuth = GoogleAccountAuthService.shared
    @ObservedObject private var quotaService = AntigravityQuotaService.shared
    @ObservedObject private var sdkModelFetcher = AntigravitySDKModelFetcher.shared
    @State private var showSignOutConfirmation = false

    // Available Models Filter & Search
    @State private var availableModelsSearchText: String = ""
    @State private var selectedProviderFilter: String = "All"

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
                    VStack(alignment: .leading, spacing: 14) {
                        // Header
                        HStack(alignment: .center) {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.18), Color.indigo.opacity(0.14)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "cpu.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Assist System Architecture")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Select the underlying reasoning and tool execution engine")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            // Architecture mode pill badge
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(settings.isMetaAssist ? Color.orange : (settings.isGoogleCloudAssist ? Color.blue : Color.purple))
                                    .frame(width: 6, height: 6)
                                Text(settings.isMetaAssist ? "Assist on Meta" : (settings.isGoogleCloudAssist ? "Google Cloud SDK" : "Native Engine"))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(settings.isMetaAssist ? Color.orange : (settings.isGoogleCloudAssist ? Color.blue : Color.purple))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background((settings.isMetaAssist ? Color.orange : (settings.isGoogleCloudAssist ? Color.blue : Color.purple)).opacity(0.1), in: Capsule())
                        }

                        // Segmented picker
                        Picker("Active Assist System", selection: $settings.assistSystemID) {
                            Text("Native Assist System")
                                .tag(AppSettings.nativeAssistSystemID)
                            Text("Assist on Google Cloud")
                                .tag(AppSettings.googleCloudAssistSystemID)
                            Text("Assist on Meta")
                                .tag(AppSettings.metaAssistSystemID)
                        }
                        .pickerStyle(.segmented)

                        if settings.assistSystemID == AppSettings.googleCloudAssistSystemID {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.subheadline)
                                Text("Assist on Google Cloud is active. Google Cloud SDK Engine (Python) runs as an application-managed background daemon.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        } else if settings.assistSystemID == AppSettings.metaAssistSystemID {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.subheadline)
                                Text("Assist on Meta is active. Meta Muse Code SDK Engine (TypeScript) runs as an application-managed background daemon.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.purple)
                                    .font(.subheadline)
                                Text("Native Assist System is active. Standard local compiler loops and multi-provider pipelines are enabled.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(14)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Separate "Assist Configuration" Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.indigo.opacity(0.14))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.indigo)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Assist Configuration")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Configure toolkits, model routing, and cloud options")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        // 1. Assist Toolkit
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Assist Toolkit")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text(settings.assistToolkit == "Cloud" ? "Cloud Tools" : "SwiftCode Tools")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(settings.assistToolkit == "Cloud" ? .blue : .indigo)
                            }

                            Picker("Assist Toolkit", selection: $settings.assistToolkit) {
                                Text("System (SwiftCode)").tag("System")
                                Text("Cloud (Official SDK)").tag("Cloud")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)

                            Text(settings.assistToolkit == "Cloud"
                                 ? "Cloud toolkit leverages the official SDK's built-in file manipulation and execution tools."
                                 : "System toolkit uses SwiftCode's native code editing, build diagnostics, and terminal tools.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        // 2. Model Routing Strategy
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Model Routing Strategy")
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                            }

                            Picker("Model Strategy", selection: $settings.assistModelRoutingStrategy) {
                                Text("Official SDK Default").tag("default")
                                Text("App Model Catalog").tag("app_models")
                                Text("Gemini Key Rotation").tag("rotation")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)

                            if settings.assistModelRoutingStrategy == "rotation" {
                                rotationKeysRow
                            } else if settings.assistModelRoutingStrategy == "app_models" {
                                appModelsStatsRow
                            }
                        }

                        Divider()

                        // 3. SwiftCode Cloud Model
                        swiftCodeCloudSection
                    }
                    .padding(14)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 1. Google Account Authentication — independent card (OAuth
                // sessions are a different credential kind from API keys).
                googleAccountCard

                // 2. AI Provider API Keys (disclosure)
                GroupBox {
                    DisclosureGroup(isExpanded: $isAPIKeysExpanded) {
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
                                    Text("Gemini API Key")
                                        .font(.caption.bold())
                                    Spacer()
                                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                                        Label("Get Key", systemImage: "arrow.up.right")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                SecureField("AIza...", text: $geminiKey)
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
                        .padding(.top, 8)
                    } label: {
                        Label("AI Provider API Keys", systemImage: "key.fill")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 3. Advanced OAuth configuration
                advancedOAuthSection

                // 4. Modern Dynamic Available Models Section
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

                        // Modern Stats Pills
                        let stats = discoveryService.getDiscoveryStats()
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "cpu")
                                    .font(.system(size: 9))
                                Text("\(stats.agentCompatible) Agent-Ready")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                            .foregroundStyle(.purple)

                            HStack(spacing: 4) {
                                Circle().fill(Color.green).frame(width: 5, height: 5)
                                Text("\(stats.total) Total")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                            .foregroundStyle(.green)

                            HStack(spacing: 4) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 9))
                                Text("\(stats.providers) Providers")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                            .foregroundStyle(.secondary)

                            if !discoveryService.hiddenProviderNames.isEmpty {
                                Text("\(discoveryService.hiddenProviderNames.count) hidden")
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            if let last = discoveryService.lastDiscoveryDate {
                                Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Modern Search Bar
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Search models by name, model ID, or provider...", text: $availableModelsSearchText)
                                .textFieldStyle(.plain)
                                .font(.caption)

                            if !availableModelsSearchText.isEmpty {
                                Button {
                                    availableModelsSearchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                        // Provider Filter Chips
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                let allFilters = ["All"] + discoveryService.modelsByProvider.map { $0.providerName }
                                ForEach(allFilters, id: \.self) { filterName in
                                    Button {
                                        selectedProviderFilter = filterName
                                    } label: {
                                        Text(filterName)
                                            .font(.system(size: 11, weight: selectedProviderFilter == filterName ? .bold : .medium))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(
                                                selectedProviderFilter == filterName
                                                    ? Color.purple.opacity(0.18)
                                                    : Color.primary.opacity(0.04),
                                                in: Capsule()
                                            )
                                            .foregroundStyle(selectedProviderFilter == filterName ? Color.purple : Color.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        // Grouped Filtered Models
                        let query = availableModelsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let filteredGroups = discoveryService.modelsByProvider.compactMap { group -> (providerName: String, models: [AssistAvailableModel])? in
                            if selectedProviderFilter != "All" && group.providerName != selectedProviderFilter {
                                return nil
                            }
                            let models = group.models.filter { model in
                                if query.isEmpty { return true }
                                return model.displayName.lowercased().contains(query) ||
                                       model.modelIdentifier.lowercased().contains(query) ||
                                       model.providerName.lowercased().contains(query)
                            }
                            return models.isEmpty ? nil : (providerName: group.providerName, models: models)
                        }

                        if filteredGroups.isEmpty {
                            VStack(spacing: 8) {
                                if discoveryService.isDiscovering {
                                    ProgressView().scaleEffect(0.8)
                                    Text("Discovering models across providers...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: query.isEmpty ? "sparkles" : "magnifyingglass")
                                        .font(.title2)
                                        .foregroundStyle(.secondary.opacity(0.5))
                                    Text(query.isEmpty ? "No models discovered. Ensure your API keys or custom endpoints are configured." : "No models found matching \"\(availableModelsSearchText)\"")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(filteredGroups, id: \.providerName) { group in
                                    VStack(alignment: .leading, spacing: 8) {
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

                                        VStack(spacing: 5) {
                                            ForEach(group.models) { model in
                                                HStack(spacing: 8) {
                                                    // Status indicator dot
                                                    Circle()
                                                        .fill(modelStatusColor(model))
                                                        .frame(width: 6, height: 6)

                                                    // Model details
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack(spacing: 6) {
                                                            Text(model.displayName)
                                                                .font(.system(size: 12, weight: .semibold))

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
                                                                HStack(spacing: 2) {
                                                                    Image(systemName: "eye.fill")
                                                                        .font(.system(size: 7))
                                                                    Text("Vision")
                                                                        .font(.system(size: 8, weight: .bold))
                                                                }
                                                                .padding(.horizontal, 4)
                                                                .padding(.vertical, 1)
                                                                .background(Color.purple.opacity(0.12))
                                                                .foregroundStyle(.purple)
                                                                .cornerRadius(3)
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
                                                        .font(.system(size: 10, weight: .medium))
                                                        .foregroundStyle(modelStatusColor(model))

                                                    // Selection button
                                                    if settings.selectedAssistModelID == model.modelIdentifier {
                                                        Image(systemName: "checkmark.circle.fill")
                                                            .font(.system(size: 14))
                                                            .foregroundStyle(.green)
                                                    } else if model.isAvailable {
                                                        Button("Select") {
                                                            settings.selectedAssistModelID = model.modelIdentifier
                                                            settings.selectedModel = model.modelIdentifier
                                                            if model.source == .appleFoundationModels || model.source == .appleFoundation || model.providerName == "Apple Foundation Models" {
                                                                FoundationModels.shared.isEnabled = true
                                                                if let appleModel = AppleFoundationModel(rawValue: model.modelIdentifier) {
                                                                    FoundationModels.shared.selectedModel = appleModel
                                                                }
                                                            } else {
                                                                FoundationModels.shared.isEnabled = false
                                                                AssistModelManager.shared.customModelID = model.modelIdentifier
                                                            }
                                                            Task {
                                                                await ModelSessionManager.shared.switchModel(to: model.modelIdentifier)
                                                                AssistModelRouter.shared.currentRuntimeModel = model
                                                                AssistManager.shared.resetActiveGoogleCloudSessionIfModelChanged(to: model.modelIdentifier)
                                                            }
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
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(settings.selectedAssistModelID == model.modelIdentifier ? Color.accentColor.opacity(0.06) : Color.primary.opacity(0.02))
                                                )
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.04), lineWidth: 1)
                                    )
                                }
                            }
                        }

                        Divider().padding(.vertical, 2)

                        // Automatic fallback rotation toggle
                        Toggle(isOn: Binding(
                            get: { fallbackRotation.isEnabled },
                            set: { fallbackRotation.isEnabled = $0 }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Automatic Fallback to Other Models")
                                    .font(.subheadline.bold())
                                Text("Rotates through all available models automatically if rate limits or network issues strike.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 5. Developer Integrations & Extensions
                GroupBox {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("Integrations & Extensions", systemImage: "puzzlepiece.extension.fill")
                                .font(.headline)
                                .foregroundColor(.indigo)
                            Spacer()
                        }

                        Text("Extend Assist with on-device Apple intelligence, Model Context Protocol servers, external app tools, and domain-specific engineering playbooks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Divider()
                            .padding(.vertical, 2)

                        // 1) Apple Foundation Models
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.green.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "apple.logo")
                                    .foregroundColor(.green)
                                    .font(.system(size: 16, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Foundation Models")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("On-device Apple Silicon intelligence without remote requests")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                showFoundationModelsSheet = true
                            } label: {
                                Label("Configure", systemImage: "slider.horizontal.3")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))

                        // 2) Model Context Protocol (MCP)
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.purple.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "network")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 16, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Model Context Protocol (MCP)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Connect stdio or remote HTTP servers for dynamic tools & context")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                showMCPServersSheet = true
                            } label: {
                                Label("Manage MCP", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))

                        // 3) Composio Integrations
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.indigo.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "link.badge.plus")
                                    .foregroundColor(.indigo)
                                    .font(.system(size: 16, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Composio Integrations")
                                        .font(.system(size: 13, weight: .semibold))
                                    if composioService.isConnected {
                                        Text("Connected")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text("External toolkits: GitHub, Slack, Calendar, Jira, Linear")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                showComposioSheet = true
                            } label: {
                                Label("Manage Composio", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))

                        // 4) Agent Skills
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "sparkles")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 16, weight: .bold))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Agent Skills")
                                        .font(.system(size: 13, weight: .semibold))
                                    let activeCount = SkillIndex.shared.skills.filter { $0.isEnabled }.count
                                    Text("\(activeCount) Active")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }
                                Text("Domain-specific engineering playbooks & autonomous workflows")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                showSkillsSheet = true
                            } label: {
                                Label("Manage Skills", systemImage: "arrow.up.right.square")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 6. Custom Model Integration Section
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

                // 7. Terminal Command Approvals
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Terminal Command Approvals", systemImage: "terminal.fill")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                            Button {
                                showingTerminalCommands = true
                            } label: {
                                Label("Manage", systemImage: "chevron.right")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .sheet(isPresented: $showingTerminalCommands) {
                            AllowedTerminalCommandsView()
                                .frame(minWidth: 560, minHeight: 520)
                        }

                        Text("Choose which terminal commands Assist may run without asking for approval, or enable Full Access to skip approval for every command.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
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
                    Text("Installing official SDK runtime for direct execution")
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
                    HStack(spacing: 12) {
                        if let err = downloadErrorMessage {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(err, forType: .string)
                            } label: {
                                Label("Copy Error", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }

                        Button("Done") {
                            isDownloadingResources = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
            .padding(28)
            .frame(width: 440)
            .interactiveDismissDisabled(!downloadCompleted && downloadErrorMessage == nil)
        }
        .alert("Sign Out of Account?", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                googleAuth.signOut()
            }
        } message: {
            // M-3: sign-out does not change the auth mode — say what actually
            // happens instead of promising a switch to API-key auth.
            Text("Are you sure you want to sign out? Google models will be unavailable until you sign in again or switch to API key authentication in Settings.")
        }
        .onAppear {
            loadAPIKeys()
            loadCachedModels()
            Task {
                await discoveryService.discoverAllModels(forceRefresh: true)
            }
        }
        .onChange(of: googleAuth.isAuthenticated) { _, _ in
            Task {
                await discoveryService.discoverAllModels(forceRefresh: true)
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

    @ViewBuilder
    // MARK: - Model Routing Strategy Rows

    /// Status row for the "Gemini Key Rotation" strategy. Extracted from the
    /// settings body: the inline if/else exceeded the type-checker's budget.
    private var rotationKeysRow: some View {
        let keyCount = AlternativeKeyManager.shared.keys.count
        let readyCount = AlternativeKeyManager.shared.keys.filter { $0.isAvailableForUse }.count
        return HStack(spacing: 8) {
            Circle()
                .fill(readyCount > 0 ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text("\(keyCount) Gemini keys saved (\(readyCount) ready)")
                .font(.system(size: 10.5, weight: .medium))
            Spacer()
            Button {
                showAlternativeKeysSheet = true
            } label: {
                Text("Manage Keys")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    /// Status row for the "App Model Catalog" strategy. Extracted from the
    /// settings body for the same reason as rotationKeysRow.
    private var appModelsStatsRow: some View {
        let stats = discoveryService.getDiscoveryStats()
        return HStack(spacing: 6) {
            Circle().fill(Color.green).frame(width: 5, height: 5)
            Text("\(stats.total) models in catalog")
                .font(.system(size: 10.5, weight: .semibold))
            Text("·").foregroundStyle(.secondary)
            Text("\(stats.providers) providers")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary)
            Text("\(stats.agentCompatible) agent-compatible")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.blue)
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    // MARK: - SwiftCode Cloud Model Section

    /// The whole "Use SwiftCode's Cloud Model" settings block. Extracted from
    /// the settings body: the quota text's interpolation plus the ternary in
    /// foregroundStyle exceeded the type-checker's budget inline.
    private var swiftCodeCloudSection: some View {
        // Hoisted so the Toggle label stays a trivial expression.
        let cloudRemaining = SCCloudModelClient.shared.remainingRequestsToday
        let cloudLimit = SCCloudConfiguration.dailyRequestLimit
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $settings.useSwiftCodeCloudModel) {
                HStack {
                    Text("Use SwiftCode's Cloud Model")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(cloudRemaining)/\(cloudLimit) left today")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(cloudRemaining > 0 ? Color.secondary : Color.orange)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .onChange(of: settings.useSwiftCodeCloudModel) { _, isOn in
                if isOn {
                    // Provision the device fingerprint the moment the user opts in.
                    // The fingerprint itself is never exposed to the UI.
                    SCCloudDeviceFingerprint.ensureFingerprint()
                    // Discover the server's models right away so the user
                    // can pick one instead of waiting for the picker to load.
                    Task { await refreshCloudModels() }
                }
            }

            Text("Adds SwiftCode's hosted cloud models to the model picker. Works with any routing strategy — no API key or sign-in required. Limited to \(cloudLimit) requests per device per day for fair use.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if settings.useSwiftCodeCloudModel {
                Divider()
                cloudModelListSection
            }
        }
    }

    @ViewBuilder
    // MARK: - SwiftCode Cloud Model List

    /// Discovered cloud models with manual refresh. The server hosts many
    /// models — this list (and the picker) is driven by live discovery,
    /// never by a hardcoded single model.
    private var cloudModelListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cloud Models")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                if isRefreshingCloudModels {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else {
                    Button("Refresh") {
                        Task { await refreshCloudModels() }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.link)
                }
            }

            if let updated = cloudModelsUpdatedAt, !cloudModels.isEmpty {
                Text("\(cloudModels.count) models · updated \(updated, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else if !isRefreshingCloudModels {
                Text("No models discovered yet — tap Refresh to ask the server which models it serves.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            ForEach(cloudModels, id: \.endpointName) { model in
                Button {
                    settings.selectedAssistModelID = model.internalID
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: settings.selectedAssistModelID == model.internalID
                              ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(settings.selectedAssistModelID == model.internalID
                                             ? Color.accentColor : Color.secondary)
                        Text(model.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                        Spacer()
                        if let blurb = model.blurb, !blurb.isEmpty {
                            Text(blurb)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            // Seed from the persisted cache; the toggle's onChange kicks off
            // a live refresh when the user opts in.
            cloudModels = SCCloudModelDiscovery.shared.models
            cloudModelsUpdatedAt = SCCloudModelDiscovery.shared.lastUpdated
        }
    }

    /// Fetches the server's model list now and updates the section state.
    private func refreshCloudModels() async {
        await MainActor.run { isRefreshingCloudModels = true }
        let fresh = await SCCloudModelDiscovery.shared.refresh()
        let updated = SCCloudModelDiscovery.shared.lastUpdated
        await MainActor.run {
            cloudModels = fresh
            cloudModelsUpdatedAt = updated
            isRefreshingCloudModels = false
        }
    }

    @ViewBuilder
    // MARK: - Google Account Authentication Card

    /// Independent Google account authentication card. OAuth sessions are a
    /// different credential kind from provider API keys, so they live in
    /// their own card — not nested inside AI Provider API Keys.
    private var googleAccountCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Google Account Authentication", systemImage: "person.badge.key.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                    googleAuthStatusBadge
                }

                if googleAuth.isAuthenticated {
                    authenticatedAccountView
                } else {
                    googleSignInControls
                }
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    /// Truthful sign-in state: not signed in, signing in, authenticated,
    /// failed, or expired — never a vague or stale label.
    private var googleAuthStatusBadge: some View {
        Group {
            if googleAuth.isAuthenticating {
                Label("Signing in…", systemImage: "progress.indicator")
                    .foregroundStyle(.secondary)
            } else if googleAuth.isAuthenticated {
                Label("Authenticated", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if googleAuth.authError != nil {
                Label("Sign-in failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else if googleAuth.lastTokenRefreshError != nil {
                Label("Session expired", systemImage: "clock.badge.exclamationmark.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Not signed in", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
    }

    /// Sign-in controls for the unauthenticated state. Ordinary sign-in stays
    /// here; low-level OAuth configuration lives under Advanced.
    private var googleSignInControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Google Auth Mode", selection: $assistGoogleAuthMode) {
                Text("Sign in with Google").tag("google_oauth")
                Text("API Key").tag("api_key")
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
            .onChange(of: assistGoogleAuthMode) { _, newValue in
                AppSettings.shared.assistGoogleAuthMode = newValue
            }

            if assistGoogleAuthMode == "google_oauth" {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
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
                                    Text("Sign in with Google")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(googleAuth.isAuthenticating)

                        if googleAuth.findAgyCLI() != nil || googleAuth.fetchAntigravityCredentialsFromKeychain() != nil {
                            Button {
                                googleAuth.signInViaCLI()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "terminal.fill")
                                    Text("Via CLI")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .disabled(googleAuth.isAuthenticating)
                            .help("Authenticate in the background using the agy CLI")
                        }
                    }

                    Text("Sign in with your Google account to use Gemini models without an API key. OAuth usage is attributed to your Google Cloud project (see Advanced below).")
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

                    if let refreshError = googleAuth.lastTokenRefreshError {
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "clock.badge.exclamationmark.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("Previous session expired: \(refreshError). Sign in again to continue.")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            } else {
                Text("API Key mode: add your Gemini API key under AI Provider API Keys below.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Advanced OAuth Configuration

    /// Low-level OAuth configuration. Ordinary sign-in stays in the Google
    /// Account card above; these fields are for project/client overrides.
    private var advancedOAuthSection: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Cloud Project ID")
                            .font(.caption2.bold())
                        TextField("my-project-id", text: Binding(
                            get: { AppSettings.shared.assistGoogleCloudProject },
                            set: { AppSettings.shared.assistGoogleCloudProject = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption2)
                        Text("Required for Sign in with Google: the Gemini API bills OAuth usage to this project. Find it in the Google Cloud console.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("OAuth Client ID Override")
                            .font(.caption2.bold())
                        TextField("Empty = SwiftCode's built-in client", text: $googleOAuthClientIDInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption2)
                            .onChange(of: googleOAuthClientIDInput) { _, newValue in
                                AppSettings.shared.assistGoogleOAuthClientIDOverride = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        Text("Only needed if you must use a different OAuth client than SwiftCode's built-in one. Applies to the next sign-in.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("OAuth Client Secret")
                                .font(.caption2.bold())
                            if googleAuth.hasKeychainClientSecret {
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(.green)
                                        .font(.caption2)
                                    Text("Saved in Keychain")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            Spacer()
                            if googleAuth.hasKeychainClientSecret {
                                Button("Clear") {
                                    googleAuth.clearClientSecret()
                                }
                                .font(.caption2)
                                .buttonStyle(.plain)
                                .foregroundColor(.red)
                            }
                        }
                        HStack(spacing: 6) {
                            SecureField("Paste client secret", text: $googleClientSecretInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption2)
                            Button("Save") {
                                googleAuth.setClientSecret(googleClientSecretInput)
                                googleClientSecretInput = ""
                            }
                            .font(.caption2)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(googleClientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("Required for Sign in with Google: Google's token endpoint rejects the sign-in without it (\"client_secret is missing.\"). Stored only in Keychain, never in the app bundle.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Advanced", systemImage: "gearshape.fill")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var authenticatedAccountView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(quotaService.fiveHourGaugeColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 19))
                        .foregroundColor(quotaService.fiveHourGaugeColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let email = googleAuth.userEmail, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    } else {
                        Text("Google Account")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    HStack(spacing: 5) {
                        Circle().fill(quotaService.fiveHourGaugeColor).frame(width: 6, height: 6)
                        Text("OAuth Active · Using Account Allowance")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !googleAuth.hasRequiredAssistScopes() {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gemini API Permissions Needed")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Your session needs updated permissions to use Assist directly with your Google account without an API key.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Update Permissions") {
                        googleAuth.reAuthenticateForAssistScopes()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }

            Divider()

            accountLimitsAllowanceCard
        }
        .padding(12)
        .background(quotaService.fiveHourGaugeColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(quotaService.fiveHourGaugeColor.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var accountLimitsAllowanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.with.needle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                    Text("Account Allowance")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    quotaService.refreshRealGoogleQuota()
                } label: {
                    if quotaService.isRefreshingQuota {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Refresh live rate limits via CLI script")
                .disabled(quotaService.isRefreshingQuota)

                Text("\(quotaService.fiveHourRemainingPercentString) Remaining")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(quotaService.fiveHourGaugeColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(quotaService.fiveHourGaugeColor)
            }

            // 5-Hour Limit
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Gemini 5-Hour Rate Limit")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(quotaService.fiveHourRemainingPercentString) remaining")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(quotaService.fiveHourGaugeColor)
                }

                ProgressView(value: quotaService.fiveHourRemainingFraction)
                    .tint(quotaService.fiveHourGaugeColor)

                HStack {
                    Text("Resets in: \(quotaService.fiveHourResetCountdownString)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Live CLI Allowance")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Weekly Limit
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Gemini Weekly Allowance")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(quotaService.weeklyRemainingPercentString) remaining")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(quotaService.weeklyGaugeColor)
                }

                ProgressView(value: quotaService.weeklyRemainingFraction)
                    .tint(quotaService.weeklyGaugeColor)

                HStack {
                    Text("Resets: \(quotaService.weeklyResetString)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Live CLI Allowance")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            quotaService.refreshRealGoogleQuota()
        }
    }

    private func loadAPIKeys() {
        openRouterKey = APIKeyManager.shared.retrieveKey(service: .openRouter)
            ?? KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey)
            ?? KeychainService.shared.get(forKey: "openrouter-api-key")
            ?? ""
        openaiKey = APIKeyManager.shared.retrieveKey(service: .openai)
            ?? KeychainService.shared.get(forKey: LLMProvider.openai.keychainKey)
            ?? KeychainService.shared.get(forKey: "openai-api-key")
            ?? KeychainService.shared.get(forKey: "openai_api_key")
            ?? ""
        anthropicKey = APIKeyManager.shared.retrieveKey(service: .anthropic)
            ?? KeychainService.shared.get(forKey: LLMProvider.anthropic.keychainKey)
            ?? KeychainService.shared.get(forKey: "anthropic-api-key")
            ?? KeychainService.shared.get(forKey: "anthropic_api_key")
            ?? ""
        geminiKey = APIKeyManager.shared.retrieveKey(service: .google)
            ?? KeychainService.shared.get(forKey: LLMProvider.google.keychainKey)
            ?? KeychainService.shared.get(forKey: "gemini-api-key")
            ?? KeychainService.shared.get(forKey: "gemini_api_key")
            ?? ""
        composioKey = ""
        googleOAuthClientIDInput = AppSettings.shared.assistGoogleOAuthClientIDOverride
    }

    private func saveAPIKeys() {
        let trimmedOR = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAI = openaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAnthropic = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGemini = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedComposio = composioKey.trimmingCharacters(in: .whitespacesAndNewlines)

        APIKeyManager.shared.storeKey(service: .openRouter, key: trimmedOR)
        APIKeyManager.shared.storeKey(service: .openai, key: trimmedOpenAI)
        APIKeyManager.shared.storeKey(service: .anthropic, key: trimmedAnthropic)
        APIKeyManager.shared.storeKey(service: .google, key: trimmedGemini)

        KeychainService.shared.set(trimmedOR, forKey: "openrouter-api-key")
        KeychainService.shared.set(trimmedOR, forKey: KeychainService.openRouterAPIKey)
        KeychainService.shared.set(trimmedOpenAI, forKey: "openai-api-key")
        KeychainService.shared.set(trimmedOpenAI, forKey: "openai_api_key")
        KeychainService.shared.set(trimmedOpenAI, forKey: LLMProvider.openai.keychainKey)
        KeychainService.shared.set(trimmedAnthropic, forKey: "anthropic-api-key")
        KeychainService.shared.set(trimmedAnthropic, forKey: "anthropic_api_key")
        KeychainService.shared.set(trimmedAnthropic, forKey: LLMProvider.anthropic.keychainKey)
        KeychainService.shared.set(trimmedGemini, forKey: "gemini-api-key")
        KeychainService.shared.set(trimmedGemini, forKey: "gemini_api_key")
        KeychainService.shared.set(trimmedGemini, forKey: LLMProvider.google.keychainKey)

        if !trimmedComposio.isEmpty {
            ComposioService.shared.saveApiKey(trimmedComposio)
            composioKey = ""
        }

        hasSavedKeys = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            hasSavedKeys = false
        }

        Task {
            await fetchOpenRouterModels()
            await discoveryService.discoverAllModels(forceRefresh: true)
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
            models: customModels.isEmpty ? [nameToSave] : customModels,
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
        downloadStatusMessage = "Running SDK installation..."
        downloadErrorMessage = nil
        downloadCompleted = false

        let bundledSDKDir = GoogleCloudSDKProcess.resolveSDKDirectory()

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
                process.arguments = ["-m", "pip", "install", "google-antigravity", "--break-system-packages", "--upgrade"]
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
                            self.downloadStatusMessage = "Official SDK installed successfully!"
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
                // Fallback: Deploy bundled Google Cloud SDK resources to user Python site-packages
                await MainActor.run {
                    self.downloadStatusMessage = "Deploying bundled SDK resources..."
                }

                if let sdkDir = bundledSDKDir {
                    let fm = FileManager.default
                    let homeDir = fm.homeDirectoryForCurrentUser.path
                    let srcSitePackages = sdkDir.appendingPathComponent("runtime/lib/python3.14/site-packages")

                    let candidateTargetDirs = [
                        "\(homeDir)/Library/Python/3.14/lib/python/site-packages",
                        "\(homeDir)/.local/lib/python3.14/site-packages",
                        "\(homeDir)/.local/lib/python3.11/site-packages",
                        "\(homeDir)/Library/Python/3.11/lib/python/site-packages"
                    ]

                    var deploySuccess = false
                    for targetSitePackages in candidateTargetDirs {
                        do {
                            try fm.createDirectory(atPath: targetSitePackages, withIntermediateDirectories: true)
                            let items = (try? fm.contentsOfDirectory(atPath: srcSitePackages.path)) ?? []
                            for item in items {
                                let srcItem = srcSitePackages.appendingPathComponent(item).path
                                let dstItem = "\(targetSitePackages)/\(item)"
                                if fm.fileExists(atPath: dstItem) {
                                    try? fm.removeItem(atPath: dstItem)
                                }
                                try fm.copyItem(atPath: srcItem, toPath: dstItem)
                            }

                            // Write executable google-antigravity launcher script
                            let launcherScript = """
                            #!/usr/bin/env python3
                            import sys
                            import os

                            for cand in [
                                os.path.expanduser("~/Library/Python/3.14/lib/python/site-packages/google/antigravity/bin/localharness"),
                                os.path.expanduser("~/.local/lib/python3.14/site-packages/google/antigravity/bin/localharness"),
                                "/opt/homebrew/lib/python3.14/site-packages/google/antigravity/bin/localharness"
                            ]:
                                if os.path.exists(cand):
                                    os.environ["ANTIGRAVITY_HARNESS_PATH"] = cand
                                    break

                            from google.antigravity.server.main import main

                            if __name__ == "__main__":
                                main()
                            """

                            for binDir in ["\(homeDir)/.local/bin", "\(homeDir)/Library/Python/3.14/bin"] {
                                try? fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
                                let binPath = "\(binDir)/google-antigravity"
                                try? launcherScript.write(toFile: binPath, atomically: true, encoding: .utf8)
                                chmod(binPath, 0o755)
                            }

                            deploySuccess = true
                            break
                        } catch {
                            lastErr = "Failed deploying to \(targetSitePackages): \(error.localizedDescription)"
                        }
                    }

                    if deploySuccess {
                        success = true
                        await MainActor.run {
                            self.downloadStatusMessage = "Official SDK resources deployed successfully!"
                            self.downloadCompleted = true
                            self.downloadErrorMessage = nil
                            self.settings.antigravityExecutionMode = "resources"
                            Task {
                                try? await GoogleCloudSDKLifecycleManager.shared.restartEngine()
                            }
                        }
                    }
                }
            }

            if success {
                // Ensure google-antigravity executable is installed in ~/.local/bin
                let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
                let launcherScript = """
                #!/usr/bin/env python3
                import sys
                import os

                for cand in [
                    os.path.expanduser("~/Library/Python/3.14/lib/python/site-packages/google/antigravity/bin/localharness"),
                    os.path.expanduser("~/.local/lib/python3.14/site-packages/google/antigravity/bin/localharness"),
                    "/opt/homebrew/lib/python3.14/site-packages/google/antigravity/bin/localharness"
                ]:
                    if os.path.exists(cand):
                        os.environ["ANTIGRAVITY_HARNESS_PATH"] = cand
                        break

                from google.antigravity.server.main import main

                if __name__ == "__main__":
                    main()
                """

                for binDir in ["\(homeDir)/.local/bin", "\(homeDir)/Library/Python/3.14/bin"] {
                    try? FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
                    let binPath = "\(binDir)/google-antigravity"
                    try? launcherScript.write(toFile: binPath, atomically: true, encoding: .utf8)
                    chmod(binPath, 0o755)
                }
            } else {
                await MainActor.run {
                    self.downloadErrorMessage = lastErr.isEmpty ? "Failed to install google-antigravity." : lastErr
                    self.downloadStatusMessage = "Installation failed."
                }
            }
        }
    }
}
