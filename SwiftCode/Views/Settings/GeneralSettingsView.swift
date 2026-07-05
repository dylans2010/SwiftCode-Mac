import SwiftUI
import Foundation
import StoreKit

// MARK: - API Key Models

enum APIKeyProvider: String, Codable, CaseIterable {
    case openRouter = "OpenRouter"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Gemini"
    case mistral = "Mistral"
    case qwen = "Qwen"
    case gitHub = "GitHub"
    case netlify = "Netlify"
    case vercel = "Vercel"

    var icon: String {
        switch self {
        case .openRouter: return "cpu"
        case .anthropic: return "sparkles"
        case .openai: return "bolt.fill"
        case .google: return "circle.grid.3x3.fill"
        case .mistral: return "wind"
        case .qwen: return "brain.head.profile"
        case .gitHub: return "chevron.left.forwardslash.chevron.right"
        case .netlify: return "cloud.fill"
        case .vercel: return "triangle.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .openRouter: return .orange
        case .anthropic: return .indigo
        case .openai: return .green
        case .google: return .blue
        case .mistral: return .orange
        case .qwen: return .purple
        case .gitHub: return .primary
        case .netlify: return .teal
        case .vercel: return .primary
        }
    }
}

struct APIKeyEntry: Identifiable, Codable {
    var id: UUID
    var name: String
    var provider: APIKeyProvider

    var keychainKey: String { "api_key_entry_\(id.uuidString)" }

    init(id: UUID = UUID(), name: String, provider: APIKeyProvider) {
        self.id = id
        self.name = name
        self.provider = provider
    }
}

// MARK: - API Key Manager

final class APIKeyManager: ObservableObject {
    static let shared = APIKeyManager()

    @Published var keys: [APIKeyEntry] = [] {
        didSet { saveMetadata() }
    }

    private let metadataKey = "apiKeyEntries"

    private init() { loadMetadata() }

    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    private func loadMetadata() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let decoded = try? JSONDecoder().decode([APIKeyEntry].self, from: data) else { return }
        keys = decoded
    }

    func add(name: String, provider: APIKeyProvider, keyValue: String) {
        if providerKeyExists(service: provider) { return }
        let entry = APIKeyEntry(name: name, provider: provider)
        KeychainService.shared.set(keyValue, forKey: entry.keychainKey)
        keys.append(entry)
        syncKey(entry, value: keyValue)
    }

    func update(_ entry: APIKeyEntry, keyValue: String) {
        KeychainService.shared.set(keyValue, forKey: entry.keychainKey)
        syncKey(entry, value: keyValue)
    }

    func delete(_ entry: APIKeyEntry) {
        KeychainService.shared.delete(forKey: entry.keychainKey)
        keys.removeAll { $0.id == entry.id }
        clearSyncedKey(for: entry.provider)
    }

    func keyValue(for entry: APIKeyEntry) -> String? {
        KeychainService.shared.get(forKey: entry.keychainKey)
    }

    // MARK: - Keychain Methods

    func storeKey(service: APIKeyProvider, key: String) {
        // Find existing entry or create new
        if let idx = keys.firstIndex(where: { $0.provider == service }) {
            update(keys[idx], keyValue: key)
        } else {
            add(name: "\(service.rawValue) Key", provider: service, keyValue: key)
        }
    }

    func retrieveKey(service: APIKeyProvider) -> String? {
        if let entry = keys.first(where: { $0.provider == service }) {
            return keyValue(for: entry)
        }
        return nil
    }

    func deleteKey(service: APIKeyProvider) {
        if let entry = keys.first(where: { $0.provider == service }) {
            delete(entry)
        }
    }

    func providerKeyExists(service: APIKeyProvider) -> Bool {
        keys.contains { $0.provider == service }
    }

    private func syncKey(_ entry: APIKeyEntry, value: String) {
        switch entry.provider {
        case .openRouter:
            KeychainService.shared.set(value, forKey: KeychainService.openRouterAPIKey)
        case .anthropic:
            KeychainService.shared.set(value, forKey: "anthropic_api_key")
        case .openai:
            KeychainService.shared.set(value, forKey: "openai_api_key")
        case .google:
            KeychainService.shared.set(value, forKey: "gemini_api_key")
        case .mistral:
            KeychainService.shared.set(value, forKey: "mistral_api_key")
        case .qwen:
            KeychainService.shared.set(value, forKey: "qwen_api_key")
        case .gitHub:
            DeploymentKeychainManager.shared.storeKey(service: .github, key: value)
        case .netlify:
            DeploymentKeychainManager.shared.storeKey(service: .netlify, key: value)
        case .vercel:
            DeploymentKeychainManager.shared.storeKey(service: .vercel, key: value)
        }
    }

    private func clearSyncedKey(for provider: APIKeyProvider) {
        switch provider {
        case .openRouter:
            KeychainService.shared.delete(forKey: KeychainService.openRouterAPIKey)
        case .anthropic:
            KeychainService.shared.delete(forKey: "anthropic_api_key")
        case .openai:
            KeychainService.shared.delete(forKey: "openai_api_key")
        case .google:
            KeychainService.shared.delete(forKey: "gemini_api_key")
        case .mistral:
            KeychainService.shared.delete(forKey: "mistral_api_key")
        case .qwen:
            KeychainService.shared.delete(forKey: "qwen_api_key")
        case .gitHub:
            DeploymentKeychainManager.shared.deleteKey(service: .github)
        case .netlify:
            DeploymentKeychainManager.shared.deleteKey(service: .netlify)
        case .vercel:
            DeploymentKeychainManager.shared.deleteKey(service: .vercel)
        }
    }

    func reset() {
        for key in keys { KeychainService.shared.delete(forKey: key.keychainKey) }
        keys = []
    }
}

// MARK: - Theme Models

struct ThemeColors: Codable, Equatable {
    var background: String
    var editorText: String
    var syntaxKeyword: String
    var syntaxString: String
    var syntaxComment: String
    var syntaxType: String
    var accent: String
    var toolbar: String
    var panelBackground: String
}

struct AppTheme: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var isBuiltIn: Bool
    var colors: ThemeColors

    static let light = AppTheme(
        id: "light", name: "Light", isBuiltIn: true,
        colors: ThemeColors(
            background: "#FFFFFF", editorText: "#000000",
            syntaxKeyword: "#AD3DA4", syntaxString: "#C41A16",
            syntaxComment: "#007400", syntaxType: "#3900A0",
            accent: "#007AFF", toolbar: "#F2F2F7", panelBackground: "#F5F5F5"
        )
    )
    static let dark = AppTheme(
        id: "dark", name: "Dark", isBuiltIn: true,
        colors: ThemeColors(
            background: "#1A1A2E", editorText: "#DCDCDC",
            syntaxKeyword: "#FC5FA3", syntaxString: "#FC6A5D",
            syntaxComment: "#6C7986", syntaxType: "#5DD8FF",
            accent: "#FF9500", toolbar: "#1C1C1E", panelBackground: "#242430"
        )
    )
    static let monokai = AppTheme(
        id: "monokai", name: "Monokai", isBuiltIn: true,
        colors: ThemeColors(
            background: "#272822", editorText: "#F8F8F2",
            syntaxKeyword: "#F92672", syntaxString: "#E6DB74",
            syntaxComment: "#75715E", syntaxType: "#66D9EF",
            accent: "#A6E22E", toolbar: "#1E1F1C", panelBackground: "#3E3D32"
        )
    )
    static let dracula = AppTheme(
        id: "dracula", name: "Dracula", isBuiltIn: true,
        colors: ThemeColors(
            background: "#282A36", editorText: "#F8F8F2",
            syntaxKeyword: "#FF79C6", syntaxString: "#F1FA8C",
            syntaxComment: "#6272A4", syntaxType: "#8BE9FD",
            accent: "#BD93F9", toolbar: "#21222C", panelBackground: "#343746"
        )
    )
    static let oneDark = AppTheme(
        id: "one_dark", name: "One Dark", isBuiltIn: true,
        colors: ThemeColors(
            background: "#282C34", editorText: "#ABB2BF",
            syntaxKeyword: "#C678DD", syntaxString: "#98C379",
            syntaxComment: "#5C6370", syntaxType: "#61AFEF",
            accent: "#E06C75", toolbar: "#21252B", panelBackground: "#2C313A"
        )
    )
    static let solarized = AppTheme(
        id: "solarized", name: "Solarized Dark", isBuiltIn: true,
        colors: ThemeColors(
            background: "#002B36", editorText: "#839496",
            syntaxKeyword: "#859900", syntaxString: "#2AA198",
            syntaxComment: "#586E75", syntaxType: "#268BD2",
            accent: "#B58900", toolbar: "#073642", panelBackground: "#073642"
        )
    )

    static let builtIns: [AppTheme] = [.light, .dark, .monokai, .dracula, .oneDark, .solarized]
}


// MARK: - Theme Manager

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var customThemes: [AppTheme] = [] {
        didSet { save() }
    }

    private let defaultsKey = "customThemes"

    private init() { load() }

    var allThemes: [AppTheme] { AppTheme.builtIns + customThemes }

    func theme(for id: String) -> AppTheme? {
        allThemes.first { $0.id == id }
    }

    func add(_ theme: AppTheme) {
        var mutable = theme
        mutable.isBuiltIn = false
        customThemes.append(mutable)
    }

    func update(_ theme: AppTheme) {
        if let idx = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[idx] = theme
        }
    }

    func delete(_ theme: AppTheme) {
        customThemes.removeAll { $0.id == theme.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customThemes) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([AppTheme].self, from: data) else { return }
        customThemes = decoded
    }

    func reset() { customThemes = [] }
}

// MARK: - Custom Agent Connection Models

struct CustomToolParameter: Identifiable, Codable {
    var id: UUID
    var name: String
    var type: String
    var paramDescription: String
    var required: Bool

    init(id: UUID = UUID(), name: String = "", type: String = "string",
         paramDescription: String = "", required: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.paramDescription = paramDescription
        self.required = required
    }
}

struct CustomAgentConnection: Identifiable, Codable {
    var id: UUID
    var name: String
    var toolDescription: String
    var apiEndpoint: String
    var parameters: [CustomToolParameter]
    var expectedOutput: String
    var swiftCodeAssistCapable: Bool
    var identificationTags: [String]

    init(id: UUID = UUID(), name: String = "", toolDescription: String = "",
         apiEndpoint: String = "", parameters: [CustomToolParameter] = [],
         expectedOutput: String = "", swiftCodeAssistCapable: Bool = false,
         identificationTags: [String] = []) {
        self.id = id
        self.name = name
        self.toolDescription = toolDescription
        self.apiEndpoint = apiEndpoint
        self.parameters = parameters
        self.expectedOutput = expectedOutput
        self.swiftCodeAssistCapable = swiftCodeAssistCapable
        self.identificationTags = identificationTags
    }

    enum CodingKeys: String, CodingKey {
        case id, name, toolDescription, apiEndpoint, parameters, expectedOutput, swiftCodeAssistCapable, identificationTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        toolDescription = try container.decode(String.self, forKey: .toolDescription)
        apiEndpoint = try container.decode(String.self, forKey: .apiEndpoint)
        parameters = try container.decode([CustomToolParameter].self, forKey: .parameters)
        expectedOutput = try container.decode(String.self, forKey: .expectedOutput)
        swiftCodeAssistCapable = try container.decodeIfPresent(Bool.self, forKey: .swiftCodeAssistCapable) ?? false
        identificationTags = try container.decodeIfPresent([String].self, forKey: .identificationTags) ?? []
    }

    var agentToolID: String { "custom_\(id.uuidString.prefix(8))" }

    func toAgentTool() -> AgentTool {
        let agentParams = parameters.map {
            AgentToolParameter(name: $0.name, type: $0.type,
                               description: $0.paramDescription, required: $0.required)
        }
        return AgentTool(
            id: agentToolID, displayName: name, description: toolDescription,
            parameters: agentParams, category: .utilities
        )
    }
}

// MARK: - Custom Tool Registry

final class CustomToolRegistry: ObservableObject {
    static let shared = CustomToolRegistry()

    @Published var connections: [CustomAgentConnection] = [] {
        didSet { save() }
    }

    private let defaultsKey = "customAgentConnections"

    private init() { load() }

    var asAgentTools: [AgentTool] { connections.map { $0.toAgentTool() } }

    private func save() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([CustomAgentConnection].self, from: data) else { return }
        connections = decoded
    }

    func reset() { connections = [] }
}

// MARK: - GeneralSettingsView

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @StateObject private var apiKeyManager = APIKeyManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var toolRegistry = CustomToolRegistry.shared
    @StateObject private var devModeManager = DeveloperModeManager.shared
    @StateObject private var entitlementManager = EntitlementManager.shared
    @StateObject private var storeManager = StoreKitManager.shared
    @StateObject private var gitHubOAuth = GitHubOAuth.shared
    @StateObject private var offlineModelManager = OfflineModelManager.shared
    @ObservedObject private var offlineModelDownloader = OfflineModelDownloader.shared

    @AppStorage("ai.routingMode") private var aiRoutingModeRawValue: String = AIRoutingMode.dynamic.rawValue
    @AppStorage("useCodexAsAgent") private var useCodexAsAgent = false

    @State private var showAddSheet = false
    @State private var selectedProvider: APIKeyProvider?
    @State private var editingEntry: APIKeyEntry?

    @State private var showAPIKeysSheet = false
    @State private var showThemeSheet = false
    @State private var showGitHubConfigSheet = false
    @State private var showAgentConnectionsSheet = false
    @State private var showSkillsSheet = false
    @State private var showCoreMLSheet = false
    @State private var showResetConfirmation = false
    @State private var showUpdatesSheet = false
    @State private var showCreditsSheet = false
    @State private var showPaywall = false
    @State private var showDeveloperDashboard = false
    @State private var showDeveloperModeEnabledAlert = false
    @State private var versionTapCount = 0

    // Quick Setup section state
    @State private var showExtensions = false
    @State private var showOfflineModelsSheet = false
    @State private var codexAPIKey: String = ""
    @State private var codexValidationMessage: String = ""
    @State private var isValidatingCodexKey = false

    var activeTheme: AppTheme {
        themeManager.theme(for: settings.selectedThemeID) ?? AppTheme.dark
    }

    var body: some View {
        NavigationStack {
            Form {
                proSection
                quickSetupSection
                aiSection
                deploymentAndAPIKeysSection
                editorSection
                Section {
                    NavigationLink {
                        AssistSettingsView()
                    } label: {
                        Label("Assist Settings", systemImage: "sparkles.rectangle.stack.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Label("Assist", systemImage: "sparkles")
                }
                dashboardSection
                fileNavigatorCustomizationSection
                themesSection
                agentConnectionsSection
                skillsSection
                if devModeManager.isDeveloperModeEnabled {
                    developerToolsSection
                }
                appManagementSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showAPIKeysSheet) {
            APIKeysManagementView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showThemeSheet) {
            ThemeManagementView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showGitHubConfigSheet) {
            GitHubConfigView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showAgentConnectionsSheet) {
            AgentConnectionsView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showCoreMLSheet) {
            CoreMLSettingsView()
                .environmentObject(settings)
        }
        .sheet(isPresented: $showSkillsSheet) {
            SkillsView()
        }
        .sheet(isPresented: $showUpdatesSheet) {
            UpdatesView()
        }
        .sheet(isPresented: $showCreditsSheet) {
            CreditsView()
        }
        .sheet(isPresented: $showExtensions) {
            ExtensionsView()
        }
        .sheet(isPresented: $showOfflineModelsSheet) {
            NavigationStack {
                OfflineModelsView()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showDeveloperDashboard) {
            DeveloperDashboardView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddEditAPIKeyView(entry: nil, provider: selectedProvider)
        }
        .sheet(item: $editingEntry) { entry in
            AddEditAPIKeyView(entry: entry)
        }
        .alert("Developer Mode Enabled", isPresented: $showDeveloperModeEnabledAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Internal debugging tools and feature flags are now available.")
        }
        .confirmationDialog(
            "Reset SwiftCode",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All Data", role: .destructive) { resetApp() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all projects, settings, API keys, themes, agent connections, and cached files. This action cannot be undone.")
        }
    }

    // MARK: - Sections

    private var aiRoutingMode: AIRoutingMode {
        get { AIRoutingMode.from(rawValue: aiRoutingModeRawValue) }
        set { aiRoutingModeRawValue = newValue.rawValue }
    }

    private var hasServerAPIKey: Bool {
        let providers: [APIKeyProvider] = [.openRouter, .anthropic, .openai, .google, .mistral, .qwen]
        return providers.contains(where: { apiKeyManager.providerKeyExists(service: $0) })
    }

    private var aiErrorMessages: [String] {
        var errors: [String] = []

        if aiRoutingMode == .dynamic && !hasServerAPIKey && offlineModelManager.defaultOfflineModelRecord() == nil {
            errors.append("Dynamic AI needs either a server API key and default offline model.")
        }

        if aiRoutingMode == .alwaysServer && !hasServerAPIKey {
            errors.append("Always Server mode requires at least one API key.")
        }

        if let downloadError = offlineModelDownloader.lastErrorMessage, !downloadError.isEmpty {
            errors.append("Offline model download failed: \(downloadError)")
        }

        return errors
    }

    private var quickSetupSection: some View {
        Section {
            // Extensions shortcut
            Button {
                showExtensions = true
            } label: {
                Label("Manage Extensions", systemImage: "puzzlepiece.extension.fill")
                    .foregroundStyle(.orange)
            }

            Button {
                showOfflineModelsSheet = true
            } label: {
                Label("Offline Models", systemImage: "externaldrive.fill")
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        gitHubOAuth.signInWithGitHub()
                    } label: {
                        HStack {
                            Label("Sign In With GitHub (Beta)", systemImage: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(.primary)

                            Spacer()

                            if gitHubOAuth.isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else if gitHubOAuth.isConnected {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(gitHubOAuth.isAuthenticating || gitHubOAuth.isConnected)

                    if gitHubOAuth.isConnected {
                        Button {
                            gitHubOAuth.signOut()
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityLabel("Log Out From GitHub")
                    }
                }

                if gitHubOAuth.isConnected {
                    let userLabel = gitHubOAuth.username.map { "Connected To GitHub (@\($0))" } ?? "Connected To GitHub"
                    Text(userLabel)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let errorMessage = gitHubOAuth.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Label("Quick Setup", systemImage: "bolt.fill")
        } footer: {
            Text("Configure your model and extensions here.")
        }
    }

    private var aiSection: some View {
        Section {
            Picker("Dynamic AI", selection: $aiRoutingModeRawValue) {
                ForEach(AIRoutingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }

            Picker("Assist Model", selection: Binding(
                get: { settings.selectedAssistModelID },
                set: { settings.selectedAssistModelID = $0 }
            )) {
                ForEach(AssistModelOption.all) { model in
                    Text("\(model.displayName) (\(model.provider))")
                        .tag(model.id)
                }
            }

            if !offlineModelManager.installedModelRecords.isEmpty {
                Picker("Default Offline Model", selection: Binding(
                    get: { offlineModelManager.defaultOfflineModelName },
                    set: { offlineModelManager.setDefaultOfflineModel($0) }
                )) {
                    ForEach(offlineModelManager.installedModelRecords) { model in
                        Text(model.modelName).tag(model.modelName)
                    }
                }
            } else {
                Text("No Offline Models Installed Yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                showOfflineModelsSheet = true
            } label: {
                Label("Offline Models", systemImage: "externaldrive.fill")
                    .foregroundStyle(.blue)
            }

            Toggle(isOn: Binding(get: { settings.appleIntelligenceEnabled }, set: { settings.appleIntelligenceEnabled = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Intelligence")
                    Text(DeviceUtilityManager.shared.isAppleIntelligenceSupported() ? "Use Apple Intelligence to help you write code, fully on device and private." : "Apple Intelligence is not available on this device. Requires a iPhone 15 Pro or an iPad with M1 chip or later.")
                        .font(.caption)
                        .foregroundStyle(DeviceUtilityManager.shared.isAppleIntelligenceSupported() ? Color.secondary : Color.red)
                }
            }
            .disabled(!DeviceUtilityManager.shared.isAppleIntelligenceSupported())

            Toggle(isOn: Binding(get: { useCodexAsAgent }, set: {
                useCodexAsAgent = $0
                settings.useCodexAsDefaultAgent = $0
                CodexManager.shared.refreshUsageMode()
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Codex as Default Agent")
                    Text("When enabled, Codex becomes the default agent for AI requests instead of SwiftCode Agent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if useCodexAsAgent {
                HStack {
                    Label("Key Visibility", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(CodexManager.shared.userHasCustomAPIKey ? "Stored securely" : "Not configured")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CodexManager.shared.userHasCustomAPIKey ? .green : .secondary)
                }

                SecureField(CodexManager.shared.userHasCustomAPIKey ? "Enter a new OpenAI API key to replace the current one" : "OpenAI API Key", text: $codexAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button("Save Codex Key") {
                        let trimmed = codexAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            KeychainService.shared.delete(forKey: KeychainService.codexUserAPIKey)
                        } else {
                            KeychainService.shared.set(trimmed, forKey: KeychainService.codexUserAPIKey)
                        }
                        CodexManager.shared.refreshUsageMode()
                        codexAPIKey = ""
                        codexValidationMessage = trimmed.isEmpty ? "User key removed. App-controlled mode will be used when an app key is available." : "Stored securely in Keychain. BYOK mode is unlimited and tracked locally only."
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Validate") {
                        Task {
                            isValidatingCodexKey = true
                            let trimmed = codexAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            let isValid = await CodexManager.shared.validateUserAPIKey(trimmed)
                            codexValidationMessage = isValid ? "Codex key validated successfully." : "Codex key validation failed."
                            isValidatingCodexKey = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(codexAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidatingCodexKey)
                }

                Text(CodexManager.shared.userHasCustomAPIKey ? "Tracked only, not limited" : "No user key found. SwiftCode will fall back to restricted app-controlled usage when available.")
                    .font(.caption)
                    .foregroundStyle(CodexManager.shared.userHasCustomAPIKey ? .green : .secondary)

                if !codexValidationMessage.isEmpty {
                    Text(codexValidationMessage)
                        .font(.caption)
                        .foregroundStyle(codexValidationMessage.contains("failed") ? .red : .green)
                }
            }

            Button {
                showCoreMLSheet = true
            } label: {
                HStack {
                    Label("Local AI", systemImage: "brain.head.profile")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(settings.coreMLEnabled ? "Enabled" : "Disabled")
                        .foregroundStyle(settings.coreMLEnabled ? .green : .secondary)
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }

            if !aiErrorMessages.isEmpty {
                ForEach(aiErrorMessages, id: \.self) { error in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Label("AI", systemImage: "brain.fill")
        } footer: {
            Text("Configure AI Providers, Offline Models, Local AI, and Dynamic AI routing.")
        }
    }

    private var deploymentAndAPIKeysSection: some View {
        Group {
            Section {
                let aiProviders: [APIKeyProvider] = [.openRouter, .anthropic, .openai, .google, .mistral, .qwen]
                ForEach(aiProviders, id: \.self) { provider in
                    apiKeyRow(for: provider)
                }
            } header: {
                Label("Deployment & API Keys", systemImage: "key.fill")
            } footer: {
                Text("Server based API keys for OpenRouter, Gemini, Claude, GPT, and other providers.")
            }

            Section {
                let deploymentProviders: [APIKeyProvider] = [.gitHub, .netlify, .vercel]
                ForEach(deploymentProviders, id: \.self) { provider in
                    apiKeyRow(for: provider)
                }
            } header: {
                Label("Deployment Providers", systemImage: "cloud.fill")
            }
        }
    }

    private func apiKeyRow(for provider: APIKeyProvider) -> some View {
        HStack {
            Label {
                Text(provider.rawValue + (apiKeyManager.providerKeyExists(service: provider) ? " ✓" : ""))
                    .foregroundStyle(apiKeyManager.providerKeyExists(service: provider) ? .green : .primary)
            } icon: {
                Image(systemName: provider.icon)
                    .foregroundStyle(apiKeyManager.providerKeyExists(service: provider) ? .green : provider.tintColor)
            }
            Spacer()
            if let entry = apiKeyManager.keys.first(where: { $0.provider == provider }) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.caption)
                        .foregroundStyle(.green)

                    if provider == .gitHub {
                        Button {
                            showGitHubConfigSheet = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onTapGesture {
                    selectedProvider = provider
                    editingEntry = entry
                }
            } else {
                Button("Setup") {
                    selectedProvider = provider
                    showAddSheet = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
    }

    private var themesSection: some View {
        Section {
            Button {
                showThemeSheet = true
            } label: {
                HStack {
                    Label("Manage Themes", systemImage: "paintbrush.fill")
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: activeTheme.colors.background))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 1))
                        Text(activeTheme.name)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
        } header: {
            Label("Themes", systemImage: "paintbrush.fill")
        } footer: {
            Text("Customize the visual appearance of the code editor. Create and save your own themes.")
        }
    }



    private var editorSection: some View {
        Section {
            Toggle(isOn: $settings.alwaysPinFilesView) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Always Pin Files View")
                    Text("Keep the file navigator always visible in the code editor")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Editor", systemImage: "pencil.and.outline")
        } footer: {
            Text("When enabled, the file navigator panel stays open by default whenever you open a project.")
        }
    }

    private var dashboardSection: some View {
        Section {
            // Layout picker
            Picker("Layout", selection: $settings.dashboardLayout) {
                ForEach(DashboardLayout.allCases, id: \.self) { layout in
                    Label(
                        layout.rawValue,
                        systemImage: layout == .grid ? "square.grid.2x2" : "list.bullet"
                    ).tag(layout)
                }
            }
            .pickerStyle(.segmented)

            // Sort order
            Picker("Sort By", selection: $settings.dashboardSortOrder) {
                ForEach(DashboardSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }

            Toggle(isOn: $settings.showProjectIcons) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Project Icons")
                    Text("Display the Swift logo icon on each project card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.showFileCount) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show File Count")
                    Text("Display the number of files on each project card")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.showLastOpenedTime) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Last Opened Time")
                    Text("Display when each project was last opened")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $settings.showFolderPreview) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Folder Preview")
                    Text("Show the first file name as a preview in list layout")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Dashboard", systemImage: "rectangle.grid.2x2")
        } footer: {
            Text("Customize how your projects appear on the Home screen. Switch between grid cards and a compact list view.")
        }
    }

    private var fileNavigatorCustomizationSection: some View {
        Section {
            Picker("Layout Style", selection: $settings.fileNavigatorLayoutStyle) {
                ForEach(FileNavigatorLayoutStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            Picker("Expand Animation", selection: $settings.fileNavigatorAnimationStyle) {
                ForEach(FileNavigatorAnimationStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }

            TextField("Folder Symbol", text: $settings.fileNavigatorFolderSymbol)
            TextField("File Symbol", text: $settings.fileNavigatorFileSymbol)

            ColorPicker("Folder Color", selection: Binding(
                get: { Color(hex: settings.fileNavigatorFolderColorHex) },
                set: { settings.fileNavigatorFolderColorHex = $0.toHex }
            ), supportsOpacity: false)

            ColorPicker("Swift File Color", selection: Binding(
                get: { Color(hex: settings.fileNavigatorSwiftFileColorHex) },
                set: { settings.fileNavigatorSwiftFileColorHex = $0.toHex }
            ), supportsOpacity: false)

            ColorPicker("Default File Color", selection: Binding(
                get: { Color(hex: settings.fileNavigatorDefaultFileColorHex) },
                set: { settings.fileNavigatorDefaultFileColorHex = $0.toHex }
            ), supportsOpacity: false)

            VStack(alignment: .leading) {
                Text("Animation Speed")
                Slider(value: $settings.fileNavigatorAnimationSpeed, in: 0.1...0.8)
            }
        } header: {
            Label("File Navigator Customization", systemImage: "folder.badge.gearshape")
        } footer: {
            Text("Customize navigator appearance and behavior in real time.")
        }
    }

    private var proSection: some View {
        Section {
            if entitlementManager.isProUser {
                HStack {
                    Label("SwiftCode Pro Member!", systemImage: "crown.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack {
                        Label("Upgrade to Pro", systemImage: "crown.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                }
            }

            Button {
                Task { try? await storeManager.restorePurchases() }
            } label: {
                Label("Restore Purchases", systemImage: "arrow.clockwise")
            }

            Button {
                AppStore.showManageSubscriptions()
            } label: {
                Label("Manage Subscription", systemImage: " person.crop.circle.badge.checkmark")
            }
        } header: {
            Label("SwiftCode Pro", systemImage: "star.fill")
        }
    }

    private var developerToolsSection: some View {
        Section {
            Button {
                showDeveloperDashboard = true
            } label: {
                Label("Developer Tools", systemImage: "wrench.and.screwdriver.fill")
            }
        } header: {
            Label("Developer Mode", systemImage: "cpu")
        }
    }

    private var agentConnectionsSection: some View {
        Section {
            Button {
                showAgentConnectionsSheet = true
            } label: {
                HStack {
                    Label("Agent Tool Connections", systemImage: "puzzlepiece.extension.fill")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(toolRegistry.connections.count) tool\(toolRegistry.connections.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
        } header: {
            Label("Agent Connections", systemImage: "puzzlepiece.extension.fill")
        } footer: {
            Text("Define custom tools the AI agent can call. Tools are registered immediately and available to the agent without app updates.")
        }
    }

    private var skillsSection: some View {
        Section {
            Button {
                showSkillsSheet = true
            } label: {
                HStack {
                    Label("Skills", systemImage: "brain")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Agent Knowledge")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
        } header: {
            Label("Agent Skills", systemImage: "brain")
        } footer: {
            Text("Import zipped skills and browse built-in skill packs used by the agent while coding.")
        }
    }

    private var appManagementSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset SwiftCode", systemImage: "trash.fill")
            }
        } header: {
            Label("App Management", systemImage: "gear.badge")
        } footer: {
            Text("Removes all stored data and resets the app to its initial state.")
        }
    }

    private static let openRouterURL = URL(string: "https://openrouter.ai")!
    private static let githubAPIDocsURL = URL(string: "https://docs.github.com/en/rest")!
    private static let swiftCodeReleasesURL = URL(string: "https://github.com/dylans2010/SwiftCode/releases")!

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                versionTapCount += 1
                if versionTapCount >= 7 {
                    devModeManager.enableDeveloperMode()
                    showDeveloperModeEnabledAlert = true
                    print("Developer Mode Enabled")
                    versionTapCount = 0
                }
            }

            HStack {
                Text("Build")
                Spacer()
                Text("1").foregroundStyle(.secondary)
            }
            Button {
                showUpdatesSheet = true
            } label: {
                Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath.circle.fill")
            }
            Button {
                showCreditsSheet = true
            } label: {
                Label("Credits", systemImage: "person.2.fill")
            }
            Link(destination: Self.swiftCodeReleasesURL) {
                Label("SwiftCode Releases", systemImage: "sparkles")
            }
            Link(destination: Self.openRouterURL) {
                Label("OpenRouter API", systemImage: "link")
            }
            Link(destination: Self.githubAPIDocsURL) {
                Label("GitHub API Docs", systemImage: "link")
            }
        } header: {
            Label("About SwiftCode", systemImage: "info.circle")
        }
    }

    // MARK: - Reset

    private func resetApp() {
        // 1. Clear all API keys from keychain
        APIKeyManager.shared.reset()
        // 2. Clear custom themes
        ThemeManager.shared.reset()
        // 3. Clear custom agent tools
        CustomToolRegistry.shared.reset()
        // 4. Clear uploaded agent skills
        AgentSkillManager.shared.resetUploadedSkills()
        // 5. Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // 6. Clear keychain tokens
        KeychainService.shared.delete(forKey: KeychainService.openRouterAPIKey)
        DeploymentKeychainManager.shared.deleteKey(service: .github)
        DeploymentKeychainManager.shared.deleteKey(service: .netlify)
        DeploymentKeychainManager.shared.deleteKey(service: .vercel)
        // 7. Clear Documents directory
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: docs, includingPropertiesForKeys: nil
        ) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // 8. Clear active project state and reload
        ProjectManager.shared.activeProject = nil
        ProjectManager.shared.activeFileNode = nil
        ProjectManager.shared.activeFileContent = ""
        ProjectManager.shared.loadProjects()
        dismiss()
    }
}

// MARK: - API Keys Management View

struct APIKeysManagementView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = APIKeyManager.shared

    @State private var showAddSheet = false
    @State private var selectedProvider: APIKeyProvider?
    @State private var editingEntry: APIKeyEntry?
    @State private var showDeleteConfirmation = false
    @State private var entryToDelete: APIKeyEntry?
    @State private var showHelpSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showHelpSheet = true
                    } label: {
                        Label("Where Do I Get Keys?", systemImage: "questionmark.circle.fill")
                            .font(.subheadline.bold())
                    }
                }

                Section("Configured Services") {
                    ForEach(APIKeyProvider.allCases, id: \.self) { provider in
                        HStack {
                            Label {
                                Text(provider.rawValue + (manager.providerKeyExists(service: provider) ? " ✓" : ""))
                                    .foregroundStyle(manager.providerKeyExists(service: provider) ? .green : .primary)
                            } icon: {
                                Image(systemName: provider.icon)
                                    .foregroundStyle(manager.providerKeyExists(service: provider) ? .green : provider.tintColor)
                            }
                            Spacer()
                            if let entry = manager.keys.first(where: { $0.provider == provider }) {
                                Text(entry.name)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Button("Setup") {
                                    selectedProvider = provider
                                    showAddSheet = true
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section("All Keys") {
                    if manager.keys.isEmpty {
                        Text("No keys added yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.keys) { entry in
                            APIKeyRowView(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture { editingEntry = entry }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        entryToDelete = entry
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("API & Deployment Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedProvider = nil
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddEditAPIKeyView(entry: nil, provider: selectedProvider)
            }
            .sheet(isPresented: $showHelpSheet) {
                APIKeysHelpView()
            }
            .sheet(item: $editingEntry) { entry in
                AddEditAPIKeyView(entry: entry)
            }
            .confirmationDialog(
                "Delete API Key",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let entry = entryToDelete { manager.delete(entry) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let name = entryToDelete?.name {
                    Text("Delete \(name)? This cannot be undone.")
                }
            }
        }
    }
}

// MARK: - API Keys Help View

struct APIKeysHelpView: View {
    @Environment(\.dismiss) private var dismiss

    let providers: [(name: String, url: String, icon: String, color: Color)] = [
        ("OpenRouter", "https://openrouter.ai/keys", "cpu", .orange),
        ("Anthropic", "https://console.anthropic.com/settings/keys", "sparkles", .indigo),
        ("OpenAI", "https://platform.openai.com/api-keys", "bolt.fill", .green),
        ("Gemini", "https://aistudio.google.com/app/apikey", "circle.grid.3x3.fill", .blue),
        ("Mistral", "https://console.mistral.ai/api-keys/", "wind", .orange),
        ("Qwen", "https://dashscope.console.aliyun.com/apiKey", "brain.head.profile", .purple),
        ("GitHub", "https://github.com/settings/tokens", "chevron.left.forwardslash.chevron.right", .primary),
        ("Netlify", "https://app.netlify.com/user/settings/applications", "cloud.fill", .teal),
        ("Vercel", "https://vercel.com/account/tokens", "triangle.fill", .primary)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("To use the AI and deployment features of SwiftCode, you'll need API keys from the respective providers. Tap a provider below to visit their website and generate a key.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }

                ForEach(providers, id: \.name) { provider in
                    Link(destination: URL(string: provider.url)!) {
                        HStack {
                            Label {
                                Text(provider.name)
                                    .foregroundColor(.primary)
                            } icon: {
                                Image(systemName: provider.icon)
                                    .foregroundStyle(provider.color)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Get API Keys")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct APIKeyRowView: View {
    let entry: APIKeyEntry
    @StateObject private var manager = APIKeyManager.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.provider.icon)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.headline)
                    Text("✓")
                        .font(.headline)
                        .foregroundStyle(.green)
                }
                Text(entry.provider.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if manager.keyValue(for: entry)?.isEmpty == false {
                    Text("Key Configured")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add / Edit API Key View

struct AddEditAPIKeyView: View {
    let entry: APIKeyEntry?
    let initialProvider: APIKeyProvider?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = APIKeyManager.shared

    @State private var name: String
    @State private var provider: APIKeyProvider
    @State private var keyValue: String
    @State private var showKey = false
    @State private var saved = false
    @State private var isValidating = false
    @State private var validationError: String?

    init(entry: APIKeyEntry?, provider: APIKeyProvider? = nil) {
        self.entry = entry
        self.initialProvider = provider
        _name = State(initialValue: entry?.name ?? "")
        _provider = State(initialValue: entry?.provider ?? provider ?? .openRouter)
        _keyValue = State(initialValue: "")
    }

    var isEditing: Bool { entry != nil }
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !keyValue.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Key Details") {
                    TextField("Key Name", text: $name)
                        .autocorrectionDisabled()

                    Picker("Provider", selection: $provider) {
                        ForEach(APIKeyProvider.allCases, id: \.self) { p in
                            Label(p.rawValue, systemImage: p.icon).tag(p)
                        }
                    }
                }

                Section {
                    HStack {
                        Group {
                            if showKey {
                                TextField("Enter API key", text: $keyValue)
                            } else {
                                SecureField("Enter API key", text: $keyValue)
                            }
                        }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .fontDesign(.monospaced)

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Key Value")
                } footer: {
                    Text("Keys are stored securely in the iOS Keychain.")
                }
            }
            .navigationTitle(isEditing ? "Edit Key" : "Add API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isValidating {
                        ProgressView()
                    } else {
                        Button(isEditing ? "Update" : "Add") {
                            Task { await validateAndSave() }
                        }
                        .disabled(!isValid)
                    }
                }
            }
            .alert("Validation Error", isPresented: Binding(
                get: { validationError != nil },
                set: { if !$0 { validationError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = validationError {
                    Text(error)
                }
            }
            .onAppear {
                if let entry {
                    keyValue = manager.keyValue(for: entry) ?? ""
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func validateAndSave() async {
        // Block duplicate provider keys unless we are editing an existing entry for that provider
        if !isEditing && manager.providerKeyExists(service: provider) {
            validationError = "A key for this provider is already configured."
            return
        }

        isValidating = true
        validationError = nil

        do {
            // Validate based on provider
            switch provider {
            case .openRouter, .anthropic, .openai, .google, .mistral, .qwen:
                let llmProvider = LLMProvider(rawValue: provider.rawValue) ?? .openRouter
                _ = try await LLMService.shared.validateAPIKey(provider: llmProvider, key: keyValue)
            case .gitHub:
                // Simple validation by fetching user info
                let url = URL(string: "https://api.github.com/user")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(keyValue)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw NSError(domain: "GitHub", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid GitHub token."])
                }
            case .netlify:
                let url = URL(string: "https://api.netlify.com/api/v1/user")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(keyValue)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw NSError(domain: "Netlify", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid Netlify token."])
                }
            case .vercel:
                let url = URL(string: "https://api.vercel.com/v2/user")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(keyValue)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw NSError(domain: "Vercel", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid Vercel token."])
                }
            }

            saveKey()
        } catch {
            validationError = error.localizedDescription
        }

        isValidating = false
    }

    private func saveKey() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEditing, let existing = entry {
            var updated = existing
            updated.name = trimmedName
            updated.provider = provider
            if let idx = manager.keys.firstIndex(where: { $0.id == existing.id }) {
                manager.keys[idx] = updated
            }
            manager.update(updated, keyValue: keyValue)
        } else {
            manager.add(name: trimmedName, provider: provider, keyValue: keyValue)
        }
        dismiss()
    }
}

// MARK: - Theme Management View

struct ThemeManagementView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    @State private var showCreateSheet = false
    @State private var editingTheme: AppTheme?

    var body: some View {
        NavigationStack {
            List {
                Section("Built In Themes") {
                    ForEach(AppTheme.builtIns) { theme in
                        ThemeRowView(theme: theme, isSelected: settings.selectedThemeID == theme.id)
                            .contentShape(Rectangle())
                            .onTapGesture { settings.selectedThemeID = theme.id }
                    }
                }

                if !themeManager.customThemes.isEmpty {
                    Section("Custom Themes") {
                        ForEach(themeManager.customThemes) { theme in
                            ThemeRowView(theme: theme, isSelected: settings.selectedThemeID == theme.id)
                                .contentShape(Rectangle())
                                .onTapGesture { settings.selectedThemeID = theme.id }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        if settings.selectedThemeID == theme.id {
                                            settings.selectedThemeID = "dark"
                                        }
                                        themeManager.delete(theme)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        editingTheme = theme
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("New Theme", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                CustomThemeEditorView(theme: nil)
                    .environmentObject(settings)
            }
            .sheet(item: $editingTheme) { theme in
                CustomThemeEditorView(theme: theme)
                    .environmentObject(settings)
            }
        }
    }
}

struct ThemeRowView: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Color swatch
            HStack(spacing: 3) {
                ForEach([
                    theme.colors.background,
                    theme.colors.syntaxKeyword,
                    theme.colors.accent,
                    theme.colors.syntaxString
                ], id: \.self) { hex in
                    Rectangle()
                        .fill(Color(hex: hex))
                        .frame(width: 16, height: 32)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.2)))

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name)
                    .font(.headline)
                Text(theme.isBuiltIn ? "Built In" : "Custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Custom Theme Editor View

struct CustomThemeEditorView: View {
    let theme: AppTheme?
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    @State private var themeName: String
    @State private var backgroundColor: Color
    @State private var editorTextColor: Color
    @State private var syntaxKeywordColor: Color
    @State private var syntaxStringColor: Color
    @State private var syntaxCommentColor: Color
    @State private var syntaxTypeColor: Color
    @State private var accentColor: Color
    @State private var toolbarColor: Color
    @State private var panelBackgroundColor: Color

    var isEditing: Bool { theme != nil }

    init(theme: AppTheme?) {
        self.theme = theme
        let t = theme ?? AppTheme.dark
        _themeName = State(initialValue: theme?.name ?? "My Theme")
        _backgroundColor = State(initialValue: Color(hex: t.colors.background))
        _editorTextColor = State(initialValue: Color(hex: t.colors.editorText))
        _syntaxKeywordColor = State(initialValue: Color(hex: t.colors.syntaxKeyword))
        _syntaxStringColor = State(initialValue: Color(hex: t.colors.syntaxString))
        _syntaxCommentColor = State(initialValue: Color(hex: t.colors.syntaxComment))
        _syntaxTypeColor = State(initialValue: Color(hex: t.colors.syntaxType))
        _accentColor = State(initialValue: Color(hex: t.colors.accent))
        _toolbarColor = State(initialValue: Color(hex: t.colors.toolbar))
        _panelBackgroundColor = State(initialValue: Color(hex: t.colors.panelBackground))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme Name") {
                    TextField("Theme Name", text: $themeName)
                        .autocorrectionDisabled()
                }

                Section("Editor Colors") {
                    ColorPicker("Background", selection: $backgroundColor, supportsOpacity: false)
                    ColorPicker("Editor Text", selection: $editorTextColor, supportsOpacity: false)
                    ColorPicker("Accent", selection: $accentColor, supportsOpacity: false)
                }

                Section("Syntax Highlighting") {
                    ColorPicker("Keywords", selection: $syntaxKeywordColor, supportsOpacity: false)
                    ColorPicker("Strings", selection: $syntaxStringColor, supportsOpacity: false)
                    ColorPicker("Comments", selection: $syntaxCommentColor, supportsOpacity: false)
                    ColorPicker("Types", selection: $syntaxTypeColor, supportsOpacity: false)
                }

                Section("UI Colors") {
                    ColorPicker("Toolbar", selection: $toolbarColor, supportsOpacity: false)
                    ColorPicker("Panel Background", selection: $panelBackgroundColor, supportsOpacity: false)
                }

                Section("Preview") {
                    themePreview
                }
            }
            .navigationTitle(isEditing ? "Edit Theme" : "New Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Create") { saveTheme() }
                        .disabled(themeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var themePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// Preview")
                .foregroundStyle(syntaxCommentColor)
            HStack(spacing: 0) {
                Text("struct ").foregroundStyle(syntaxKeywordColor)
                Text("MyView").foregroundStyle(syntaxTypeColor)
                Text(": View {").foregroundStyle(editorTextColor)
            }
            HStack(spacing: 0) {
                Text("    let title = ").foregroundStyle(editorTextColor)
                Text("\"Hello\"").foregroundStyle(syntaxStringColor)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func saveTheme() {
        let colors = ThemeColors(
            background: backgroundColor.toHex,
            editorText: editorTextColor.toHex,
            syntaxKeyword: syntaxKeywordColor.toHex,
            syntaxString: syntaxStringColor.toHex,
            syntaxComment: syntaxCommentColor.toHex,
            syntaxType: syntaxTypeColor.toHex,
            accent: accentColor.toHex,
            toolbar: toolbarColor.toHex,
            panelBackground: panelBackgroundColor.toHex
        )
        if isEditing, let existing = theme {
            let updated = AppTheme(
                id: existing.id,
                name: themeName.trimmingCharacters(in: .whitespacesAndNewlines),
                isBuiltIn: false,
                colors: colors
            )
            themeManager.update(updated)
        } else {
            let newTheme = AppTheme(
                id: UUID().uuidString,
                name: themeName.trimmingCharacters(in: .whitespacesAndNewlines),
                isBuiltIn: false,
                colors: colors
            )
            themeManager.add(newTheme)
            settings.selectedThemeID = newTheme.id
        }
        dismiss()
    }
}

// MARK: - GitHub Configuration View

struct GitHubConfigView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private static let savedIndicatorDuration: TimeInterval = 2.0

    @State private var githubToken: String = ""
    @State private var showToken = false
    @State private var tokenSaved = false

    @StateObject private var permManager = RepoPermManager.shared

    var body: some View {
        NavigationStack {
            Form {

                // Git Identity
                Section {
                    TextField("Name (e.g. Jane Doe)", text: $settings.gitUserName)
                        .autocorrectionDisabled()
                    TextField("Email (e.g. jane@example.com)", text: $settings.gitUserEmail)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                } header: {
                    Label("Git Identity", systemImage: "person.fill")
                } footer: {
                    Text("Used in commit messages across all repositories.")
                }

                // Key Recommendation
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended: Personal Access Token (Classic)")
                            .font(.subheadline.bold())

                        Text("For full integration with SwiftCode (repository creation, commits, and deployments), we recommend using a 'Classic' token (ghp_).")
                            .font(.caption)

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Classic (ghp_):")
                                .font(.caption.bold())
                            Text("Supports all repository operations and is generally more reliable for full developer workflows.")
                                .font(.caption2)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fine-grained (github_pat_):")
                                .font(.caption.bold())
                            Text("Good for limiting access to specific repositories, but may cause permission issues with automated deployments.")
                                .font(.caption2)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Which GitHub Key Is Recommended", systemImage: "lightbulb.fill")
                }

                // SSH & HTTPS Authentication
                Section {
                    TextField("SSH Key Path", text: $settings.sshKeyPath)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("HTTPS Auth Token", text: $settings.httpsAuthToken)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Label("Authentication", systemImage: "lock.shield.fill")
                } footer: {
                    Text("Configure SSH key path or HTTPS authentication token for Git operations.")
                }

                // Advanced Git Options
                Section {
                    Toggle("Auto Fetch Repositories", isOn: $settings.autoFetchRepositories)
                    Toggle("Auto Pull Before Commit", isOn: $settings.autoPullBeforeCommit)
                    Toggle("Workflow Monitoring", isOn: $settings.workflowMonitoringEnabled)
                } header: {
                    Label("Git Automation", systemImage: "gearshape.2.fill")
                } footer: {
                    Text("Automatic fetch keeps your local copy in sync. Auto pull before commit prevents merge conflicts.")
                }

                // Commit Message Template
                Section {
                    TextField("e.g. [Feature] {message}", text: $settings.commitMessageTemplate)
                        .autocorrectionDisabled()
                } header: {
                    Label("Commit Template", systemImage: "text.badge.checkmark")
                } footer: {
                    Text("Define a template for commit messages. Use {message} as a placeholder for the actual message.")
                }

                // Repository Permissions
                Section {
                    if permManager.isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Checking Permissions…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else if permManager.hasChecked {
                        if let error = permManager.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        } else if permManager.permissions.isEmpty {
                            Text("No scopes detected. Your token may have no listed scopes or uses fine-grained permissions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(permManager.permissions) { perm in
                                HStack(spacing: 12) {
                                    Image(systemName: perm.icon)
                                        .foregroundStyle(.blue)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(perm.scope)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .fontDesign(.monospaced)
                                        Text(perm.humanReadable)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        Button {
                            Task { await permManager.fetchPermissions() }
                        } label: {
                            Label("Check Permissions", systemImage: "arrow.clockwise")
                                .font(.callout)
                        }
                    } else {
                        Button {
                            Task { await permManager.fetchPermissions() }
                        } label: {
                            Label("Check Permissions", systemImage: "checkmark.shield.fill")
                                .foregroundStyle(.blue)
                        }
                        Text("Tap here to see what scopes your current GitHub token has.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Label("Repository Permissions", systemImage: "lock.open.fill")
                } footer: {
                    Text("Permissions are determined by your GitHub token's OAuth scopes.")
                }
            }
            .navigationTitle("GitHub & Git Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                githubToken = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
            }
        }
    }
}

// MARK: - Agent Connections View

struct AgentConnectionsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var registry = CustomToolRegistry.shared

    @State private var showAddSheet = false
    @State private var editingConnection: CustomAgentConnection?

    var body: some View {
        NavigationStack {
            List {
                if registry.connections.isEmpty {
                    ContentUnavailableView(
                        "No Custom Tools",
                        systemImage: "puzzlepiece.extension",
                        description: Text("Add custom tools to extend the AI agent's capabilities.")
                    )
                } else {
                    ForEach(registry.connections) { connection in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(connection.name)
                                    .font(.headline)
                                Spacer()
                                Text("ID: \(connection.agentToolID)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fontDesign(.monospaced)
                            }
                            Text(connection.toolDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if !connection.apiEndpoint.isEmpty {
                                Text(connection.apiEndpoint)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                            if !connection.parameters.isEmpty {
                                Text("\(connection.parameters.count) Parameter\(connection.parameters.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if connection.swiftCodeAssistCapable {
                                Text("SwiftCode Assist Capable")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { editingConnection = connection }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                registry.connections.removeAll { $0.id == connection.id }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agent Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                CustomToolEditorView(connection: nil)
            }
            .sheet(item: $editingConnection) { connection in
                CustomToolEditorView(connection: connection)
            }
        }
    }
}

// MARK: - Custom Tool Editor View

struct CustomToolEditorView: View {
    let connection: CustomAgentConnection?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var registry = CustomToolRegistry.shared

    @State private var name: String
    @State private var toolDescription: String
    @State private var apiEndpoint: String
    @State private var expectedOutput: String
    @State private var parameters: [CustomToolParameter]
    @State private var swiftCodeAssistCapable: Bool
    @State private var showAddParameter = false
    @State private var showAdvancedBuilder = false

    var isEditing: Bool { connection != nil }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !toolDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(connection: CustomAgentConnection?) {
        self.connection = connection
        _name = State(initialValue: connection?.name ?? "")
        _toolDescription = State(initialValue: connection?.toolDescription ?? "")
        _apiEndpoint = State(initialValue: connection?.apiEndpoint ?? "")
        _expectedOutput = State(initialValue: connection?.expectedOutput ?? "")
        _parameters = State(initialValue: connection?.parameters ?? [])
        _swiftCodeAssistCapable = State(initialValue: connection?.swiftCodeAssistCapable ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tool Info") {
                    TextField("Tool Name", text: $name)
                        .autocorrectionDisabled()
                    TextField("Description", text: $toolDescription, axis: .vertical)
                        .lineLimit(3)
                }

                Section {
                    TextField("API Endpoint URL", text: $apiEndpoint)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("Expected Output Description", text: $expectedOutput, axis: .vertical)
                        .lineLimit(2)
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("The agent will send JSON POST requests to this URL with the parameters as the request body.")
                }

                Section {
                    ForEach($parameters) { $param in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Parameter Name", text: $param.name)
                                .autocorrectionDisabled()
                                .font(.headline)
                            TextField("Description", text: $param.paramDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Picker("Type", selection: $param.type) {
                                    Text("string").tag("string")
                                    Text("number").tag("number")
                                    Text("boolean").tag("boolean")
                                }
                                .pickerStyle(.segmented)
                                Toggle("Required", isOn: $param.required)
                                    .labelsHidden()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in parameters.remove(atOffsets: offsets) }

                    Button {
                        parameters.append(CustomToolParameter())
                    } label: {
                        Label("Add Parameter", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Parameters")
                        Spacer()
                        if !parameters.isEmpty {
                            EditButton()
                                .font(.caption)
                        }
                    }
                }

                Section("Assist API") {
                    Toggle("SwiftCode Assist Capable", isOn: $swiftCodeAssistCapable)
                    if swiftCodeAssistCapable {
                        Text("Identifier added: \(AssistCapability.toolIdentifier)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !isEditing {
                    Section {
                        Button {
                            showAdvancedBuilder = true
                        } label: {
                            Label("Build Custon Tool", systemImage: "wrench.and.screwdriver.fill")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Advanced")
                    } footer: {
                        Text("Build a fully custom tool with HTTP configuration, headers, body templates, and parameter definitions.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Tool" : "New Tool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Add") { saveTool() }
                        .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showAdvancedBuilder) {
                CustomToolBuilderView()
            }
        }
    }

    private func saveTool() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = toolDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEditing, let existing = connection {
            var updated = existing
            updated.name = trimmedName
            updated.toolDescription = trimmedDesc
            updated.apiEndpoint = apiEndpoint
            updated.expectedOutput = expectedOutput
            updated.parameters = parameters
            updated.swiftCodeAssistCapable = swiftCodeAssistCapable
            updated.identificationTags = AssistCapability.identifiers(enabled: swiftCodeAssistCapable)
            if let idx = registry.connections.firstIndex(where: { $0.id == existing.id }) {
                registry.connections[idx] = updated
            }
        } else {
            let newConn = CustomAgentConnection(
                name: trimmedName,
                toolDescription: trimmedDesc,
                apiEndpoint: apiEndpoint,
                parameters: parameters,
                expectedOutput: expectedOutput,
                swiftCodeAssistCapable: swiftCodeAssistCapable,
                identificationTags: AssistCapability.identifiers(enabled: swiftCodeAssistCapable)
            )
            registry.connections.append(newConn)
        }
        dismiss()
    }
}

// MARK: - CoreML Settings View

struct CoreMLSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var codingManager = CodingManager.shared

    @State private var importedModels: [URL] = []
    @State private var showModelImporter = false
    @State private var modelToDelete: URL?
    @State private var showDeleteConfirmation = false
    @State private var importError: String?
    @State private var showImportError = false
    @State private var deleteError: String?
    @State private var showDeleteError = false

    private static let coreMLExtensions: Set<String> = ["mlmodel", "mlmodelc", "mlpackage"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Local Inference", isOn: $settings.coreMLEnabled)
                    if settings.coreMLEnabled {
                        Toggle("Hybrid Mode (CoreML + API)", isOn: $settings.coreMLHybridMode)
                    }
                } header: {
                    Label("CoreML", systemImage: "brain.head.profile")
                } footer: {
                    Text("When enabled, the agent uses an on-device CoreML model for code completion, analysis, and offline assistance.")
                }

                if settings.coreMLEnabled {
                    Section {
                        if importedModels.isEmpty {
                            Text("No Models Imported")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(importedModels, id: \.lastPathComponent) { model in
                                HStack {
                                    Image(systemName: "cube.fill")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.lastPathComponent)
                                            .font(.headline)
                                        Text(model.pathExtension.uppercased())
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settings.coreMLSelectedModel == model.lastPathComponent {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    settings.coreMLSelectedModel = model.lastPathComponent
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        modelToDelete = model
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }

                        Button {
                            showModelImporter = true
                        } label: {
                            Label("Import .mlmodel", systemImage: "square.and.arrow.down")
                        }
                    } header: {
                        Label("Imported Models", systemImage: "cube.fill")
                    } footer: {
                        Text("Models are stored in Documents/Models and are accessible from the app's directory on the Files app.")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Usage Limit")
                                Spacer()
                                Text("\(Int(settings.coreMLUsageLimit)) Requests/Session")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Slider(value: $settings.coreMLUsageLimit, in: 10...500, step: 10)
                                .tint(.purple)
                        }

                        if !settings.coreMLSelectedModel.isEmpty {
                            HStack {
                                Text("Active Model")
                                Spacer()
                                Text(settings.coreMLSelectedModel)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        Label("Configuration", systemImage: "slider.horizontal.3")
                    }

                    Section {
                        Label("Local Code Completion", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Code Analysis", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Syntax Prediction", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Project Summarization", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Label("Offline AI Assistance", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } header: {
                        Label("Supported Use Cases", systemImage: "list.bullet")
                    } footer: {
                        Text("These use cases are available when a compatible CoreML model is imported and local inference is enabled.")
                    }
                }
            }
            .navigationTitle("CoreML Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                importedModels = codingManager.listModels()
            }
            .sheet(isPresented: $showModelImporter) {
                FileImporterRepresentableView(
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { urls in
                    showModelImporter = false
                    guard let url = urls.first else { return }
                    do {
                        let ext = url.pathExtension.lowercased()
                        guard Self.coreMLExtensions.contains(ext) else {
                            importError = "Only .mlmodel, .mlmodelc, and .mlpackage files are supported."
                            showImportError = true
                            return
                        }
                        let accessing = url.startAccessingSecurityScopedResource()
                        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                        let imported = try codingManager.importModel(from: url)
                        importedModels = codingManager.listModels()
                        if settings.coreMLSelectedModel.isEmpty {
                            settings.coreMLSelectedModel = imported.lastPathComponent
                        }
                    } catch {
                        importError = error.localizedDescription
                        showImportError = true
                    }
                }
            }
            .alert("Import Failed", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "An unknown error occurred.")
            }
            .confirmationDialog(
                "Delete Model",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let model = modelToDelete {
                        do {
                            try codingManager.deleteModel(named: model.lastPathComponent)
                            if settings.coreMLSelectedModel == model.lastPathComponent {
                                settings.coreMLSelectedModel = ""
                            }
                            importedModels = codingManager.listModels()
                        } catch {
                            deleteError = error.localizedDescription
                            showDeleteError = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let name = modelToDelete?.lastPathComponent {
                    Text("Delete \(name)? This cannot be undone.")
                }
            }
            .alert("Delete Failed", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "An unknown error occurred.")
            }
        }
    }
}
