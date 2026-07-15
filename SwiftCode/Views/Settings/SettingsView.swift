import SwiftUI
import AppKit

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

// MARK: - App Settings

@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private var saveTask: Task<Void, Never>?

    var selectedModel: String {
        didSet { debouncedSave("selectedModel", selectedModel) }
    }
    var customModel: String {
        didSet { debouncedSave("customModel", customModel) }
    }
    var selectedAssistModelID: String {
        didSet { debouncedSave("selectedAssistModelID", selectedAssistModelID) }
    }
    var autoSave: Bool {
        didSet { debouncedSave("autoSave", autoSave) }
    }
    var editorFontSize: Double {
        didSet { debouncedSave("editorFontSize", editorFontSize) }
    }
    var useDarkTheme: Bool {
        didSet { debouncedSave("useDarkTheme", useDarkTheme) }
    }
    var fileHeaderAuthor: String {
        didSet { debouncedSave("fileHeaderAuthor", fileHeaderAuthor) }
    }
    var fileHeaderCustomComment: String {
        didSet { debouncedSave("fileHeaderCustomComment", fileHeaderCustomComment) }
    }

    // MARK: Theme
    var selectedThemeID: String {
        didSet { debouncedSave("selectedThemeID", selectedThemeID) }
    }

    // MARK: Git / GitHub Configuration
    var gitUserName: String {
        didSet { debouncedSave("gitUserName", gitUserName) }
    }
    var gitUserEmail: String {
        didSet { debouncedSave("gitUserEmail", gitUserEmail) }
    }
    var defaultBranch: String {
        didSet { debouncedSave("defaultBranch", defaultBranch) }
    }
    var defaultGitHubRepo: String {
        didSet { debouncedSave("defaultGitHubRepo", defaultGitHubRepo) }
    }

    // MARK: Saved Repositories
    var savedRepositories: [SavedRepository] = [] {
        didSet { persistSavedRepositories() }
    }
    var startOnNewProject: Bool {
        didSet { debouncedSave("startOnNewProject", startOnNewProject) }
    }

    // MARK: Extended Git Configuration
    var sshKeyPath: String {
        didSet { debouncedSave("sshKeyPath", sshKeyPath) }
    }
    var httpsAuthToken: String {
        didSet { debouncedSave("httpsAuthToken", httpsAuthToken) }
    }
    var autoFetchRepositories: Bool {
        didSet { debouncedSave("autoFetchRepositories", autoFetchRepositories) }
    }
    var autoPullBeforeCommit: Bool {
        didSet { debouncedSave("autoPullBeforeCommit", autoPullBeforeCommit) }
    }
    var commitMessageTemplate: String {
        didSet { debouncedSave("commitMessageTemplate", commitMessageTemplate) }
    }
    var workflowMonitoringEnabled: Bool {
        didSet { debouncedSave("workflowMonitoringEnabled", workflowMonitoringEnabled) }
    }

    // MARK: Dashboard Customization
    var dashboardLayout: DashboardLayout {
        didSet { debouncedSave("dashboardLayout", dashboardLayout.rawValue) }
    }
    var dashboardSortOrder: DashboardSortOrder {
        didSet { debouncedSave("dashboardSortOrder", dashboardSortOrder.rawValue) }
    }
    var showProjectIcons: Bool {
        didSet { debouncedSave("showProjectIcons", showProjectIcons) }
    }
    var showFolderPreview: Bool {
        didSet { debouncedSave("showFolderPreview", showFolderPreview) }
    }
    var alwaysPinFilesView: Bool {
        didSet { debouncedSave("alwaysPinFilesView", alwaysPinFilesView) }
    }
    var showFileCount: Bool {
        didSet { debouncedSave("showFileCount", showFileCount) }
    }
    var showLastOpenedTime: Bool {
        didSet { debouncedSave("showLastOpenedTime", showLastOpenedTime) }
    }

    // MARK: CoreML
    var coreMLEnabled: Bool {
        didSet { debouncedSave("coreMLEnabled", coreMLEnabled) }
    }
    var coreMLHybridMode: Bool {
        didSet { debouncedSave("coreMLHybridMode", coreMLHybridMode) }
    }
    var coreMLSelectedModel: String {
        didSet { debouncedSave("coreMLSelectedModel", coreMLSelectedModel) }
    }
    var coreMLUsageLimit: Double {
        didSet { debouncedSave("coreMLUsageLimit", coreMLUsageLimit) }
    }

    // MARK: File Navigator Customization
    var fileNavigatorLayoutStyle: FileNavigatorLayoutStyle {
        didSet { debouncedSave("fileNavigatorLayoutStyle", fileNavigatorLayoutStyle.rawValue) }
    }
    var fileNavigatorAnimationStyle: FileNavigatorAnimationStyle {
        didSet { debouncedSave("fileNavigatorAnimationStyle", fileNavigatorAnimationStyle.rawValue) }
    }
    var fileNavigatorFolderSymbol: String {
        didSet { debouncedSave("fileNavigatorFolderSymbol", fileNavigatorFolderSymbol) }
    }
    var fileNavigatorFileSymbol: String {
        didSet { debouncedSave("fileNavigatorFileSymbol", fileNavigatorFileSymbol) }
    }
    var fileNavigatorFolderColorHex: String {
        didSet { debouncedSave("fileNavigatorFolderColorHex", fileNavigatorFolderColorHex) }
    }
    var fileNavigatorSwiftFileColorHex: String {
        didSet { debouncedSave("fileNavigatorSwiftFileColorHex", fileNavigatorSwiftFileColorHex) }
    }
    var fileNavigatorDefaultFileColorHex: String {
        didSet { debouncedSave("fileNavigatorDefaultFileColorHex", fileNavigatorDefaultFileColorHex) }
    }
    var fileNavigatorAnimationSpeed: Double {
        didSet { debouncedSave("fileNavigatorAnimationSpeed", fileNavigatorAnimationSpeed) }
    }
    var codeSuggestionsEnabled: Bool {
        didSet { debouncedSave("codeSuggestionsEnabled", codeSuggestionsEnabled) }
    }
    var appleIntelligenceEnabled: Bool {
        didSet { debouncedSave("appleIntelligenceEnabled", appleIntelligenceEnabled) }
    }
    var useCodexAsDefaultAgent: Bool {
        didSet {
            debouncedSave("useCodexAsDefaultAgent", useCodexAsDefaultAgent)
            debouncedSave("useCodexAsAgent", useCodexAsDefaultAgent)
        }
    }
    var hasCompletedOnboarding: Bool {
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

// MARK: - Settings Categories (Sidebar)

private enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case aiConfiguration = "AI Configuration"
    case github = "GitHub"
    case editor = "Editor"
    case fileTemplates = "File Templates"
    case extensions = "Extensions"
    case about = "About"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .aiConfiguration: return "sparkles"
        case .github: return "arrow.triangle.2.circlepath"
        case .editor: return "doc.text"
        case .fileTemplates: return "doc.badge.plus"
        case .extensions: return "puzzlepiece.extension.fill"
        case .about: return "info.circle"
        }
    }

    /// Matches System Settings' sidebar tinted-icon style.
    var symbolTint: Color {
        switch self {
        case .aiConfiguration: return .purple
        case .github: return .indigo
        case .editor: return .orange
        case .fileTemplates: return .teal
        case .extensions: return .pink
        case .about: return .gray
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var selectedCategory: SettingsCategory? = .aiConfiguration
    @State private var searchText = ""

    @State private var openRouterKey: String = ""
    @State private var githubToken: String = ""
    @State private var showOpenRouterKey = false
    @State private var showGitHubToken = false
    @State private var keySaved = false
    @State private var tokenSaved = false
    @State private var customModelInput: String = ""
    @State private var customModelSaved = false
    @State private var showExtensions = false

    private var filteredCategories: [SettingsCategory] {
        guard !searchText.isEmpty else { return SettingsCategory.allCases }
        return SettingsCategory.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredCategories, selection: $selectedCategory) { category in
                Label {
                    Text(category.rawValue)
                } icon: {
                    Image(systemName: category.symbolName)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(category.symbolTint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .tag(category)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .searchable(text: $searchText, placement: .sidebar, prompt: "Search Settings")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detailContent(for: selectedCategory ?? .aiConfiguration)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(28)
            }
            .background(.background)
            .navigationTitle((selectedCategory ?? .aiConfiguration).rawValue)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 480, idealHeight: 540)
        .sheet(isPresented: $showExtensions) {
            ExtensionsView()
                .frame(minWidth: 560, minHeight: 440)
        }
        .onAppear {
            openRouterKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey) ?? ""
            githubToken = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
            customModelInput = settings.customModel
        }
    }

    // MARK: - Detail Routing

    @ViewBuilder
    private func detailContent(for category: SettingsCategory) -> some View {
        switch category {
        case .aiConfiguration: aiConfigurationDetail
        case .github: gitHubDetail
        case .editor: editorDetail
        case .fileTemplates: fileTemplatesDetail
        case .extensions: extensionsDetail
        case .about: aboutDetail
        }
    }

    // MARK: - AI Configuration

    private var aiConfigurationDetail: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                LabeledContent("OpenRouter API Key") {
                    HStack(spacing: 8) {
                        if openRouterKey.isEmpty {
                            Text("Not Set")
                                .font(.callout)
                                .foregroundStyle(.red)
                        } else {
                            Text("••••••••\(String(openRouterKey.suffix(4)))")
                                .font(.callout.monospaced())
                                .foregroundStyle(.green)
                        }
                        Button {
                            showOpenRouterKey.toggle()
                        } label: {
                            Image(systemName: showOpenRouterKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(showOpenRouterKey ? "Hide key" : "Reveal key")
                    }
                }

                if showOpenRouterKey {
                    TextField("sk-or-xxxxxxxxxxxxxxxx", text: $openRouterKey)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button {
                            KeychainService.shared.set(openRouterKey, forKey: KeychainService.openRouterAPIKey)
                            keySaved = true
                            showOpenRouterKey = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                keySaved = false
                            }
                        } label: {
                            Label(keySaved ? "Saved!" : "Save Key", systemImage: keySaved ? "checkmark.circle.fill" : "key.fill")
                        }
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
            } header: {
                Text("OpenRouter")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom OpenRouter Model")
                        .font(.headline)
                    Text("Enter any valid OpenRouter model ID.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("e.g. mistralai/mistral-7b-instruct", text: $customModelInput)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button {
                            let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            settings.customModel = trimmed
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
                        }
                        .foregroundStyle(customModelSaved ? .green : .purple)
                    }
                }
            } header: {
                Text("Custom Model")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - GitHub

    private var gitHubDetail: some View {
        Form {
            Section {
                LabeledContent("GitHub Personal Access Token") {
                    HStack(spacing: 8) {
                        if githubToken.isEmpty {
                            Text("Not Set")
                                .font(.callout)
                                .foregroundStyle(.red)
                        } else {
                            Text("••••••••\(String(githubToken.suffix(4)))")
                                .font(.callout.monospaced())
                                .foregroundStyle(.green)
                        }
                        Button {
                            showGitHubToken.toggle()
                        } label: {
                            Image(systemName: showGitHubToken ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(showGitHubToken ? "Hide token" : "Reveal token")
                    }
                }

                if showGitHubToken {
                    TextField("ghp_xxxxxxxxxxxx", text: $githubToken)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Spacer()
                        Button {
                            KeychainService.shared.set(githubToken, forKey: KeychainService.githubToken)
                            tokenSaved = true
                            showGitHubToken = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                tokenSaved = false
                            }
                        } label: {
                            Label(tokenSaved ? "Saved!" : "Save Token", systemImage: tokenSaved ? "checkmark.circle.fill" : "key.fill")
                        }
                        .foregroundStyle(tokenSaved ? .green : .blue)
                    }
                }
            } header: {
                Text("Authentication")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Editor

    private var editorDetail: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle("Auto Save", isOn: $settings.autoSave)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(settings.editorFontSize))pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.editorFontSize, in: 10...24, step: 1)
                        .tint(.orange)
                }

                Toggle("Dark Theme", isOn: $settings.useDarkTheme)
            } header: {
                Text("Editor")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - File Templates

    private var fileTemplatesDetail: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Author Name")
                        .font(.headline)
                    Text("Used in the // Created by header of new Swift files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                TextField("Your Name", text: $settings.fileHeaderAuthor)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Comment")
                        .font(.headline)
                    Text("Added as a second header comment in new Swift files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                TextField("Made with SwiftCode", text: $settings.fileHeaderCustomComment)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("File Templates")
            } footer: {
                Text("New .swift files will include:\n// Created by <Author> on <Date>.\n// <Custom Comment>")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Extensions

    private var extensionsDetail: some View {
        Form {
            Section {
                Button {
                    showExtensions = true
                } label: {
                    Label("Manage Extensions…", systemImage: "puzzlepiece.extension.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } header: {
                Text("Extensions")
            } footer: {
                Text("Install, enable, disable, or create custom extensions for SwiftCode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutDetail: some View {
        Form {
            Section {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Build", value: "1")
            }

            Section {
                Link(destination: Self.openRouterURL) {
                    Label("OpenRouter API", systemImage: "link")
                }
                Link(destination: Self.githubDocsURL) {
                    Label("GitHub API Docs", systemImage: "link")
                }
            } header: {
                Text("Resources")
            }
        }
        .formStyle(.grouped)
    }

    // SAFETY: static, hardcoded, well-formed URL literals — force-unwrap cannot fail.
    private static let openRouterURL = URL(string: "https://openrouter.ai")!
    // SAFETY: static, hardcoded, well-formed URL literals — force-unwrap cannot fail.
    private static let githubDocsURL = URL(string: "https://docs.github.com/en/rest")!
}

#Preview {
    SettingsView()
        .environment(AppSettings.shared)
}
