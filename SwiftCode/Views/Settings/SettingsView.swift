import SwiftUI

// MARK: - Saved Repository Model

struct SavedRepository: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var owner: String
    var repositoryURL: String
    var defaultBranch: String
    var localProjectPath: String?

    init(id: UUID = UUID(), name: String, owner: String, repositoryURL: String, defaultBranch: String = "main", localProjectPath: String? = nil) {
        self.id = id
        self.name = name
        self.owner = owner
        self.repositoryURL = repositoryURL
        self.defaultBranch = defaultBranch
        self.localProjectPath = localProjectPath
    }
}

// MARK: - Dashboard Layout

enum DashboardLayout: String, Codable, CaseIterable {
    case grid = "Grid"
    case list = "List"
}

enum DashboardSortOrder: String, Codable, CaseIterable {
    case name = "Name"
    case lastOpened = "Last Opened"
    case creationDate = "Creation Date"
}

enum FileNavigatorLayoutStyle: String, Codable, CaseIterable {
    case compact = "Compact"
    case expanded = "Expanded"
}

enum FileNavigatorAnimationStyle: String, Codable, CaseIterable {
    case easeInOut = "Ease In/Out"
    case spring = "Spring"
    case bouncy = "Bouncy"
}

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private var saveTask: Task<Void, Never>?

    @Published var selectedModel: String {
        didSet { debouncedSave("selectedModel", selectedModel) }
    }
    @Published var customModel: String {
        didSet { debouncedSave("customModel", customModel) }
    }
    @Published var selectedAssistModelID: String {
        didSet { debouncedSave("selectedAssistModelID", selectedAssistModelID) }
    }
    @Published var autoSave: Bool {
        didSet { debouncedSave("autoSave", autoSave) }
    }
    @Published var editorFontSize: Double {
        didSet { debouncedSave("editorFontSize", editorFontSize) }
    }
    @Published var useDarkTheme: Bool {
        didSet { debouncedSave("useDarkTheme", useDarkTheme) }
    }
    @Published var fileHeaderAuthor: String {
        didSet { debouncedSave("fileHeaderAuthor", fileHeaderAuthor) }
    }
    @Published var fileHeaderCustomComment: String {
        didSet { debouncedSave("fileHeaderCustomComment", fileHeaderCustomComment) }
    }

    // MARK: - Theme
    @Published var selectedThemeID: String {
        didSet { debouncedSave("selectedThemeID", selectedThemeID) }
    }

    // MARK: - Git / GitHub Configuration
    @Published var gitUserName: String {
        didSet { debouncedSave("gitUserName", gitUserName) }
    }
    @Published var gitUserEmail: String {
        didSet { debouncedSave("gitUserEmail", gitUserEmail) }
    }
    @Published var defaultBranch: String {
        didSet { debouncedSave("defaultBranch", defaultBranch) }
    }
    @Published var defaultGitHubRepo: String {
        didSet { debouncedSave("defaultGitHubRepo", defaultGitHubRepo) }
    }

    // MARK: - Saved Repositories
    @Published var savedRepositories: [SavedRepository] = [] {
        didSet { persistSavedRepositories() }
    }
    @Published var startOnNewProject: Bool {
        didSet { debouncedSave("startOnNewProject", startOnNewProject) }
    }

    // MARK: - Extended Git Configuration
    @Published var sshKeyPath: String {
        didSet { debouncedSave("sshKeyPath", sshKeyPath) }
    }
    @Published var httpsAuthToken: String {
        didSet { debouncedSave("httpsAuthToken", httpsAuthToken) }
    }
    @Published var autoFetchRepositories: Bool {
        didSet { debouncedSave("autoFetchRepositories", autoFetchRepositories) }
    }
    @Published var autoPullBeforeCommit: Bool {
        didSet { debouncedSave("autoPullBeforeCommit", autoPullBeforeCommit) }
    }
    @Published var commitMessageTemplate: String {
        didSet { debouncedSave("commitMessageTemplate", commitMessageTemplate) }
    }
    @Published var workflowMonitoringEnabled: Bool {
        didSet { debouncedSave("workflowMonitoringEnabled", workflowMonitoringEnabled) }
    }

    // MARK: - Dashboard Customization
    @Published var dashboardLayout: DashboardLayout {
        didSet { debouncedSave("dashboardLayout", dashboardLayout.rawValue) }
    }
    @Published var dashboardSortOrder: DashboardSortOrder {
        didSet { debouncedSave("dashboardSortOrder", dashboardSortOrder.rawValue) }
    }
    @Published var showProjectIcons: Bool {
        didSet { debouncedSave("showProjectIcons", showProjectIcons) }
    }
    @Published var showFolderPreview: Bool {
        didSet { debouncedSave("showFolderPreview", showFolderPreview) }
    }
    @Published var alwaysPinFilesView: Bool {
        didSet { debouncedSave("alwaysPinFilesView", alwaysPinFilesView) }
    }
    @Published var showFileCount: Bool {
        didSet { debouncedSave("showFileCount", showFileCount) }
    }
    @Published var showLastOpenedTime: Bool {
        didSet { debouncedSave("showLastOpenedTime", showLastOpenedTime) }
    }

    // MARK: - CoreML
    @Published var coreMLEnabled: Bool {
        didSet { debouncedSave("coreMLEnabled", coreMLEnabled) }
    }
    @Published var coreMLHybridMode: Bool {
        didSet { debouncedSave("coreMLHybridMode", coreMLHybridMode) }
    }
    @Published var coreMLSelectedModel: String {
        didSet { debouncedSave("coreMLSelectedModel", coreMLSelectedModel) }
    }
    @Published var coreMLUsageLimit: Double {
        didSet { debouncedSave("coreMLUsageLimit", coreMLUsageLimit) }
    }

    // MARK: - File Navigator Customization
    @Published var fileNavigatorLayoutStyle: FileNavigatorLayoutStyle {
        didSet { debouncedSave("fileNavigatorLayoutStyle", fileNavigatorLayoutStyle.rawValue) }
    }
    @Published var fileNavigatorAnimationStyle: FileNavigatorAnimationStyle {
        didSet { debouncedSave("fileNavigatorAnimationStyle", fileNavigatorAnimationStyle.rawValue) }
    }
    @Published var fileNavigatorFolderSymbol: String {
        didSet { debouncedSave("fileNavigatorFolderSymbol", fileNavigatorFolderSymbol) }
    }
    @Published var fileNavigatorFileSymbol: String {
        didSet { debouncedSave("fileNavigatorFileSymbol", fileNavigatorFileSymbol) }
    }
    @Published var fileNavigatorFolderColorHex: String {
        didSet { debouncedSave("fileNavigatorFolderColorHex", fileNavigatorFolderColorHex) }
    }
    @Published var fileNavigatorSwiftFileColorHex: String {
        didSet { debouncedSave("fileNavigatorSwiftFileColorHex", fileNavigatorSwiftFileColorHex) }
    }
    @Published var fileNavigatorDefaultFileColorHex: String {
        didSet { debouncedSave("fileNavigatorDefaultFileColorHex", fileNavigatorDefaultFileColorHex) }
    }
    @Published var fileNavigatorAnimationSpeed: Double {
        didSet { debouncedSave("fileNavigatorAnimationSpeed", fileNavigatorAnimationSpeed) }
    }
    @Published var codeSuggestionsEnabled: Bool {
        didSet { debouncedSave("codeSuggestionsEnabled", codeSuggestionsEnabled) }
    }
    @Published var appleIntelligenceEnabled: Bool {
        didSet { debouncedSave("appleIntelligenceEnabled", appleIntelligenceEnabled) }
    }
    @Published var useCodexAsDefaultAgent: Bool {
        didSet {
            debouncedSave("useCodexAsDefaultAgent", useCodexAsDefaultAgent)
            debouncedSave("useCodexAsAgent", useCodexAsDefaultAgent)
        }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { debouncedSave("hasCompletedOnboarding", hasCompletedOnboarding) }
    }

    // MARK: - Debounced Save

    private func debouncedSave(_ key: String, _ value: Any) {
        // Cancel previous save task
        saveTask?.cancel()

        // Schedule new save after a short delay to batch multiple changes
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    /// `true` when the user has chosen a custom OpenRouter model ID
    var isUsingCustomModel: Bool {
        !customModel.isEmpty && selectedModel == customModel
    }


    private init() {
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? OpenRouterModel.defaults.first?.id ?? ""
        customModel   = UserDefaults.standard.string(forKey: "customModel") ?? ""
        selectedAssistModelID = UserDefaults.standard.string(forKey: "selectedAssistModelID") ?? AssistModelOption.swiftCodeBalanced.id
        autoSave = UserDefaults.standard.object(forKey: "autoSave") as? Bool ?? true
        editorFontSize = UserDefaults.standard.object(forKey: "editorFontSize") as? Double ?? 14
        useDarkTheme = UserDefaults.standard.object(forKey: "useDarkTheme") as? Bool ?? true
        fileHeaderAuthor = UserDefaults.standard.string(forKey: "fileHeaderAuthor") ?? ""
        fileHeaderCustomComment = UserDefaults.standard.string(forKey: "fileHeaderCustomComment") ?? "Made with SwiftCode"
        selectedThemeID = UserDefaults.standard.string(forKey: "selectedThemeID") ?? "dark"
        gitUserName = UserDefaults.standard.string(forKey: "gitUserName") ?? ""
        gitUserEmail = UserDefaults.standard.string(forKey: "gitUserEmail") ?? ""
        defaultBranch = UserDefaults.standard.string(forKey: "defaultBranch") ?? "main"
        defaultGitHubRepo = UserDefaults.standard.string(forKey: "defaultGitHubRepo") ?? ""
        startOnNewProject = UserDefaults.standard.object(forKey: "startOnNewProject") as? Bool ?? false
        sshKeyPath = UserDefaults.standard.string(forKey: "sshKeyPath") ?? ""
        httpsAuthToken = UserDefaults.standard.string(forKey: "httpsAuthToken") ?? ""
        autoFetchRepositories = UserDefaults.standard.object(forKey: "autoFetchRepositories") as? Bool ?? false
        autoPullBeforeCommit = UserDefaults.standard.object(forKey: "autoPullBeforeCommit") as? Bool ?? false
        commitMessageTemplate = UserDefaults.standard.string(forKey: "commitMessageTemplate") ?? ""
        workflowMonitoringEnabled = UserDefaults.standard.object(forKey: "workflowMonitoringEnabled") as? Bool ?? true
        dashboardLayout = DashboardLayout(rawValue: UserDefaults.standard.string(forKey: "dashboardLayout") ?? "") ?? .grid
        dashboardSortOrder = DashboardSortOrder(rawValue: UserDefaults.standard.string(forKey: "dashboardSortOrder") ?? "") ?? .lastOpened
        showProjectIcons = UserDefaults.standard.object(forKey: "showProjectIcons") as? Bool ?? true
        showFolderPreview = UserDefaults.standard.object(forKey: "showFolderPreview") as? Bool ?? false
        alwaysPinFilesView = UserDefaults.standard.object(forKey: "alwaysPinFilesView") as? Bool ?? false
        showFileCount = UserDefaults.standard.object(forKey: "showFileCount") as? Bool ?? true
        showLastOpenedTime = UserDefaults.standard.object(forKey: "showLastOpenedTime") as? Bool ?? true
        coreMLEnabled = UserDefaults.standard.object(forKey: "coreMLEnabled") as? Bool ?? false
        coreMLHybridMode = UserDefaults.standard.object(forKey: "coreMLHybridMode") as? Bool ?? false
        coreMLSelectedModel = UserDefaults.standard.string(forKey: "coreMLSelectedModel") ?? ""
        coreMLUsageLimit = UserDefaults.standard.object(forKey: "coreMLUsageLimit") as? Double ?? 100
        fileNavigatorLayoutStyle = FileNavigatorLayoutStyle(rawValue: UserDefaults.standard.string(forKey: "fileNavigatorLayoutStyle") ?? "") ?? .compact
        fileNavigatorAnimationStyle = FileNavigatorAnimationStyle(rawValue: UserDefaults.standard.string(forKey: "fileNavigatorAnimationStyle") ?? "") ?? .easeInOut
        fileNavigatorFolderSymbol = UserDefaults.standard.string(forKey: "fileNavigatorFolderSymbol") ?? "folder.fill"
        fileNavigatorFileSymbol = UserDefaults.standard.string(forKey: "fileNavigatorFileSymbol") ?? "doc.fill"
        fileNavigatorFolderColorHex = UserDefaults.standard.string(forKey: "fileNavigatorFolderColorHex") ?? "#5E86FF"
        fileNavigatorSwiftFileColorHex = UserDefaults.standard.string(forKey: "fileNavigatorSwiftFileColorHex") ?? "#FF9F0A"
        fileNavigatorDefaultFileColorHex = UserDefaults.standard.string(forKey: "fileNavigatorDefaultFileColorHex") ?? "#9FA8DA"
        fileNavigatorAnimationSpeed = UserDefaults.standard.object(forKey: "fileNavigatorAnimationSpeed") as? Double ?? 0.22
        codeSuggestionsEnabled = UserDefaults.standard.object(forKey: "codeSuggestionsEnabled") as? Bool ?? false
        appleIntelligenceEnabled = UserDefaults.standard.object(forKey: "appleIntelligenceEnabled") as? Bool ?? false
        useCodexAsDefaultAgent = UserDefaults.standard.object(forKey: "useCodexAsAgent") as? Bool ?? UserDefaults.standard.object(forKey: "useCodexAsDefaultAgent") as? Bool ?? false
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        // Load saved repositories
        loadSavedRepositories()
    }

    // MARK: - Saved Repositories Persistence

    private static let savedReposKey = "savedRepositories"

    private func persistSavedRepositories() {
        if let data = try? JSONEncoder().encode(savedRepositories) {
            UserDefaults.standard.set(data, forKey: Self.savedReposKey)
        }
    }

    private func loadSavedRepositories() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedReposKey),
              let decoded = try? JSONDecoder().decode([SavedRepository].self, from: data) else { return }
        savedRepositories = decoded
    }

    func addRepository(_ repo: SavedRepository) {
        savedRepositories.append(repo)
    }

    func removeRepository(_ repo: SavedRepository) {
        savedRepositories.removeAll { $0.id == repo.id }
    }
}

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
