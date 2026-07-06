import SwiftUI
import Combine

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
