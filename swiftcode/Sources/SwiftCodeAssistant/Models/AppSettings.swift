import Foundation
import Observation

@MainActor
@Observable
public final class AppSettings: Sendable {
    public static let shared = AppSettings()

    private static let knownSoundIDs: Set<String> = [
        "custom.chill.ambient_rise", "custom.chill.calm_bell",
        "custom.chill.cloud", "custom.chill.drift",
        "custom.chill.soft_bloom", "custom.chill.velvet",
        "custom.error.attention",
        "custom.message.message", "custom.message.ping",
        "custom.message.presence", "custom.message.whisper",
        "custom.notification.arrival", "custom.notification.ripple",
        "custom.notification.signal", "custom.notification.soft_notify",
        "custom.satisfying.click_bloom", "custom.satisfying.perfect",
        "custom.satisfying.resolve", "custom.satisfying.soft_chime",
        "custom.satisfying.spark", "custom.satisfying.velvet_pop",
        "custom.success.complete", "custom.success.confirmed",
        "custom.success.done", "custom.success.ready",
        "custom.vibe.echo", "custom.vibe.flux", "custom.vibe.glow",
        "custom.vibe.neon", "custom.vibe.pulse", "custom.vibe.wave",
        "custom.warning.caution",
    ]

    private static func isKnownSoundID(_ id: String) -> Bool {
        id == "none" || id.hasPrefix("system_") || knownSoundIDs.contains(id)
    }

    public static let nativeAssistSystemID = "com.swiftcode.assist.native"
    public static let googleCloudAssistSystemID = "com.swiftcode.Assist.Google-Cloud"
    public static let metaAssistSystemID = "com.swiftcode.Assist.Meta"
    public static let openRouterAssistSystemID = "com.swiftcode.assist.openrouter"
    public static let openCodeAssistSystemID = "com.swiftcode.assist.opencode"
    public static let hermesAssistSystemID = "com.swiftcode.assist.hermes"

    public var assistSystemID: String {
        didSet { debouncedSave("assistSystemID", assistSystemID) }
    }

    public var isGoogleCloudAssist: Bool {
        assistSystemID == Self.googleCloudAssistSystemID
    }

    public var isMetaAssist: Bool {
        assistSystemID == Self.metaAssistSystemID
    }

    public var isOpenRouterAssist: Bool {
        assistSystemID == Self.openRouterAssistSystemID
    }

    public var isOpenCodeAssist: Bool {
        assistSystemID == Self.openCodeAssistSystemID
    }

    public var isHermesAssist: Bool {
        assistSystemID == Self.hermesAssistSystemID
    }

    public static let defaultAssistToolkit = "System"

    public var assistToolkit: String {
        didSet {
            debouncedSave("assistToolkit", assistToolkit)
            UserDefaults.standard.set(assistToolkit, forKey: "assist.assistToolkit")
        }
    }

    public var isProviderToolkit: Bool {
        assistToolkit.caseInsensitiveCompare("provider") == .orderedSame
            || assistToolkit.caseInsensitiveCompare("cloud") == .orderedSame
    }

    public var activeProviderToolkitName: String {
        if isOpenRouterAssist {
            return "OpenRouter SDK"
        } else if isOpenCodeAssist {
            return "OpenCode SDK"
        } else if isHermesAssist {
            return "Hermes tools"
        } else if isMetaAssist {
            return "Muse SDK"
        } else if isGoogleCloudAssist {
            return "Antigravity SDK"
        } else {
            return "Provider SDK"
        }
    }

    public var activeCloudToolkitName: String {
        activeProviderToolkitName
    }

    public var assistAutomaticallySwitchModels: Bool {
        didSet {
            debouncedSave("assistAutomaticallySwitchModels", assistAutomaticallySwitchModels)
            UserDefaults.standard.set(assistAutomaticallySwitchModels, forKey: "assist.automaticallySwitchModels")
        }
    }

    public var assistUseProviderModels: Bool {
        didSet {
            debouncedSave("assistUseProviderModels", assistUseProviderModels)
            UserDefaults.standard.set(assistUseProviderModels, forKey: "assist.useProviderModels")
        }
    }

    public static let defaultMetaAssistModelID = "muse-wonder-1.0"
    public static let defaultMetaReasoningEffort = "high"

    public var metaAssistModelID: String {
        didSet {
            debouncedSave("metaAssistModelID", metaAssistModelID)
            UserDefaults.standard.set(metaAssistModelID, forKey: "assist.metaAssistModelID")
        }
    }

    public var metaReasoningEffort: String {
        didSet {
            debouncedSave("metaReasoningEffort", metaReasoningEffort)
            UserDefaults.standard.set(metaReasoningEffort, forKey: "assist.metaReasoningEffort")
        }
    }

    public var otherModelsWithMetaSDK: Bool {
        didSet {
            debouncedSave("otherModelsWithMetaSDK", otherModelsWithMetaSDK)
            UserDefaults.standard.set(otherModelsWithMetaSDK, forKey: "assist.otherModelsWithMetaSDK")
        }
    }

    public var swiftCodeCloudWithMetaSDK: Bool {
        didSet {
            debouncedSave("swiftCodeCloudWithMetaSDK", swiftCodeCloudWithMetaSDK)
            UserDefaults.standard.set(swiftCodeCloudWithMetaSDK, forKey: "assist.swiftCodeCloudWithMetaSDK")
            if swiftCodeCloudWithMetaSDK {
                #if canImport(Security)
                let store: any SecretStore = KeychainSecretStore()
                #else
                let store: any SecretStore = FileSecretStore()
                #endif
                if store.readString(SecretAccount.scCloudFingerprint) == nil {
                    let fresh = SCCloudProvider.provisionFingerprint()
                    try? store.write(Data(fresh.utf8), for: SecretAccount.scCloudFingerprint)
                }
            }
        }
    }

    public var useOtherModelsWhenRateLimited: Bool {
        didSet {
            debouncedSave("useOtherModelsWhenRateLimited", useOtherModelsWhenRateLimited)
            UserDefaults.standard.set(useOtherModelsWhenRateLimited, forKey: "assist.useOtherModelsWhenRateLimited")
        }
    }

    public var metaSelectedOtherModelID: String {
        didSet {
            debouncedSave("metaSelectedOtherModelID", metaSelectedOtherModelID)
            UserDefaults.standard.set(metaSelectedOtherModelID, forKey: "assist.metaSelectedOtherModelID")
        }
    }

    public var metaSelectedOtherModelProvider: String {
        didSet {
            debouncedSave("metaSelectedOtherModelProvider", metaSelectedOtherModelProvider)
            UserDefaults.standard.set(metaSelectedOtherModelProvider, forKey: "assist.metaSelectedOtherModelProvider")
        }
    }

    public var useMetaSlashCommands: Bool {
        didSet {
            debouncedSave("useMetaSlashCommands", useMetaSlashCommands)
            UserDefaults.standard.set(useMetaSlashCommands, forKey: "assist.useMetaSlashCommands")
        }
    }

    public var reverseEnabled: Bool {
        didSet {
            debouncedSave("reverseEnabled", reverseEnabled)
            UserDefaults.standard.set(reverseEnabled, forKey: "assist.reverseEnabled")
        }
    }

    public var reverseBridgePath: String {
        didSet {
            debouncedSave("reverseBridgePath", reverseBridgePath)
            UserDefaults.standard.set(reverseBridgePath, forKey: "assist.reverseBridgePath")
        }
    }

    public var reverseReaDir: String {
        didSet {
            debouncedSave("reverseReaDir", reverseReaDir)
            UserDefaults.standard.set(reverseReaDir, forKey: "assist.reverseReaDir")
        }
    }

    public var enableUserMemory: Bool {
        didSet {
            debouncedSave("enableUserMemory", enableUserMemory)
            UserDefaults.standard.set(enableUserMemory, forKey: "assist.enableUserMemory")
        }
    }

    public var assistToolkitDisplayName: String {
        if isProviderToolkit {
            return "Provider (\(activeProviderToolkitName))"
        } else {
            return "System (SwiftCode)"
        }
    }

    public var onlyUseFreeModels: Bool {
        didSet {
            debouncedSave("onlyUseFreeModels", onlyUseFreeModels)
            UserDefaults.standard.set(onlyUseFreeModels, forKey: "assist.onlyUseFreeModels")
            NotificationCenter.default.post(name: NSNotification.Name("AssistModelEligibilityPolicyDidChange"), object: nil)
            validateCurrentSelectionsForEligibility()
        }
    }

    public var swiftCloudModelsEnabled: Bool {
        didSet { debouncedSave("swiftCloudModelsEnabled", swiftCloudModelsEnabled) }
    }

    public var useSavedModels: Bool {
        didSet {
            debouncedSave("useSavedModels", useSavedModels)
            UserDefaults.standard.set(useSavedModels, forKey: "assist.useSavedModels")
        }
    }

    public var alternativeKeysEnabled: Bool {
        didSet {
            debouncedSave("alternativeKeysEnabled", alternativeKeysEnabled)
            UserDefaults.standard.set(alternativeKeysEnabled, forKey: "assist.alternativeKeysEnabled")
        }
    }

    public var assistModelRoutingStrategy: String {
        didSet {
            debouncedSave("assistModelRoutingStrategy", assistModelRoutingStrategy)
            UserDefaults.standard.set(assistModelRoutingStrategy, forKey: "assist.modelRoutingStrategy")
            if assistModelRoutingStrategy == "rotation" {
                alternativeKeysEnabled = true
                useSavedModels = false
            } else if assistModelRoutingStrategy == "app_models" {
                alternativeKeysEnabled = false
                useSavedModels = true
            } else {
                alternativeKeysEnabled = false
                useSavedModels = false
            }
        }
    }

    public var useSwiftCodeCloudModel: Bool {
        didSet {
            debouncedSave("useSwiftCodeCloudModel", useSwiftCodeCloudModel)
            UserDefaults.standard.set(useSwiftCodeCloudModel, forKey: "assist.useSwiftCodeCloudModel")
        }
    }

    public var assistGoogleAuthMode: String {
        didSet {
            debouncedSave("assist_google_auth_mode", assistGoogleAuthMode)
            UserDefaults.standard.set(assistGoogleAuthMode, forKey: "assist_google_auth_mode")
        }
    }

    public var assistGoogleCloudProject: String {
        didSet {
            debouncedSave("assist_google_cloud_project", assistGoogleCloudProject)
            UserDefaults.standard.set(assistGoogleCloudProject, forKey: "assist_google_cloud_project")
        }
    }

    public var assistGoogleOAuthClientIDOverride: String {
        didSet {
            debouncedSave("assist_google_oauth_client_id_override", assistGoogleOAuthClientIDOverride)
            UserDefaults.standard.set(assistGoogleOAuthClientIDOverride, forKey: "assist_google_oauth_client_id_override")
        }
    }

    public var antigravityExecutionMode: String {
        didSet {
            debouncedSave("antigravity_execution_mode", antigravityExecutionMode)
            UserDefaults.standard.set(antigravityExecutionMode, forKey: "antigravity_execution_mode")
        }
    }

    public var selectedModel: String {
        didSet {
            debouncedSave("selectedModel", selectedModel)
            if selectedAssistModelID != selectedModel {
                selectedAssistModelID = selectedModel
            }
        }
    }
    public var customModel: String {
        didSet { debouncedSave("customModel", customModel) }
    }
    public var customModelProviderID: String {
        didSet {
            debouncedSave("assist_custom_model_provider_id", customModelProviderID)
            UserDefaults.standard.set(customModelProviderID, forKey: "assist_custom_model_provider_id")
        }
    }
    public var selectedAssistModelID: String {
        didSet {
            debouncedSave("selectedAssistModelID", selectedAssistModelID)
            if selectedModel != selectedAssistModelID {
                selectedModel = selectedAssistModelID
            }
        }
    }
    public var autoSave: Bool {
        didSet { debouncedSave("autoSave", autoSave) }
    }
    public var editorFontSize: Double {
        didSet { debouncedSave("editorFontSize", editorFontSize) }
    }
    public var useDarkTheme: Bool {
        didSet { debouncedSave("useDarkTheme", useDarkTheme) }
    }
    public var fileHeaderAuthor: String {
        didSet { debouncedSave("fileHeaderAuthor", fileHeaderAuthor) }
    }
    public var fileHeaderCustomComment: String {
        didSet { debouncedSave("fileHeaderCustomComment", fileHeaderCustomComment) }
    }

    public var selectedThemeID: String {
        didSet { debouncedSave("selectedThemeID", selectedThemeID) }
    }

    public var gitPath: String {
        didSet { debouncedSave("gitPath", gitPath) }
    }
    public var gitUserName: String {
        didSet { debouncedSave("gitUserName", gitUserName) }
    }
    public var gitUserEmail: String {
        didSet { debouncedSave("gitUserEmail", gitUserEmail) }
    }
    public var defaultBranch: String {
        didSet { debouncedSave("defaultBranch", defaultBranch) }
    }
    public var defaultGitHubRepo: String {
        didSet { debouncedSave("defaultGitHubRepo", defaultGitHubRepo) }
    }

    public var savedRepositories: [SavedRepository] = [] {
        didSet { persistSavedRepositories() }
    }
    public var startOnNewProject: Bool {
        didSet { debouncedSave("startOnNewProject", startOnNewProject) }
    }

    public var sshKeyPath: String {
        didSet { debouncedSave("sshKeyPath", sshKeyPath) }
    }
    public var httpsAuthToken: String {
        didSet { debouncedSave("httpsAuthToken", httpsAuthToken) }
    }
    public var autoFetchRepositories: Bool {
        didSet { debouncedSave("autoFetchRepositories", autoFetchRepositories) }
    }
    public var autoPullBeforeCommit: Bool {
        didSet { debouncedSave("autoPullBeforeCommit", autoPullBeforeCommit) }
    }
    public var commitMessageTemplate: String {
        didSet { debouncedSave("commitMessageTemplate", commitMessageTemplate) }
    }
    public var workflowMonitoringEnabled: Bool {
        didSet { debouncedSave("workflowMonitoringEnabled", workflowMonitoringEnabled) }
    }

    public var dashboardLayout: DashboardLayout {
        didSet { debouncedSave("dashboardLayout", dashboardLayout.rawValue) }
    }
    public var dashboardSortOrder: DashboardSortOrder {
        didSet { debouncedSave("dashboardSortOrder", dashboardSortOrder.rawValue) }
    }
    public var showProjectIcons: Bool {
        didSet { debouncedSave("showProjectIcons", showProjectIcons) }
    }
    public var showFolderPreview: Bool {
        didSet { debouncedSave("showFolderPreview", showFolderPreview) }
    }
    public var alwaysPinFilesView: Bool {
        didSet { debouncedSave("alwaysPinFilesView", alwaysPinFilesView) }
    }
    public var showFileCount: Bool {
        didSet { debouncedSave("showFileCount", showFileCount) }
    }
    public var showLastOpenedTime: Bool {
        didSet { debouncedSave("showLastOpenedTime", showLastOpenedTime) }
    }

    public var coreMLEnabled: Bool {
        didSet { debouncedSave("coreMLEnabled", coreMLEnabled) }
    }
    public var coreMLHybridMode: Bool {
        didSet { debouncedSave("coreMLHybridMode", coreMLHybridMode) }
    }
    public var coreMLSelectedModel: String {
        didSet { debouncedSave("coreMLSelectedModel", coreMLSelectedModel) }
    }
    public var coreMLUsageLimit: Double {
        didSet { debouncedSave("coreMLUsageLimit", coreMLUsageLimit) }
    }

    public var fileNavigatorLayoutStyle: FileNavigatorLayoutStyle {
        didSet { debouncedSave("fileNavigatorLayoutStyle", fileNavigatorLayoutStyle.rawValue) }
    }
    public var fileNavigatorAnimationStyle: FileNavigatorAnimationStyle {
        didSet { debouncedSave("fileNavigatorAnimationStyle", fileNavigatorAnimationStyle.rawValue) }
    }
    public var fileNavigatorFolderSymbol: String {
        didSet { debouncedSave("fileNavigatorFolderSymbol", fileNavigatorFolderSymbol) }
    }
    public var fileNavigatorFileSymbol: String {
        didSet { debouncedSave("fileNavigatorFileSymbol", fileNavigatorFileSymbol) }
    }
    public var fileNavigatorFolderColorHex: String {
        didSet { debouncedSave("fileNavigatorFolderColorHex", fileNavigatorFolderColorHex) }
    }
    public var fileNavigatorSwiftFileColorHex: String {
        didSet { debouncedSave("fileNavigatorSwiftFileColorHex", fileNavigatorSwiftFileColorHex) }
    }
    public var fileNavigatorDefaultFileColorHex: String {
        didSet { debouncedSave("fileNavigatorDefaultFileColorHex", fileNavigatorDefaultFileColorHex) }
    }
    public var fileNavigatorAnimationSpeed: Double {
        didSet { debouncedSave("fileNavigatorAnimationSpeed", fileNavigatorAnimationSpeed) }
    }
    public var codeSuggestionsEnabled: Bool {
        didSet { debouncedSave("codeSuggestionsEnabled", codeSuggestionsEnabled) }
    }
    public var appleIntelligenceEnabled: Bool {
        didSet { debouncedSave("appleIntelligenceEnabled", appleIntelligenceEnabled) }
    }
    public var useCodexAsDefaultAgent: Bool {
        didSet {
            debouncedSave("useCodexAsDefaultAgent", useCodexAsDefaultAgent)
            debouncedSave("useCodexAsAgent", useCodexAsDefaultAgent)
        }
    }
    public var hasCompletedOnboarding: Bool {
        didSet { debouncedSave("hasCompletedOnboarding", hasCompletedOnboarding) }
    }

    public var saveProjectsOnCustomFolder: Bool {
        didSet { debouncedSave("saveProjectsOnCustomFolder", saveProjectsOnCustomFolder) }
    }
    public var customProjectsFolder: String {
        didSet { debouncedSave("customProjectsFolder", customProjectsFolder) }
    }

    public var defaultOrganization: String {
        didSet { debouncedSave("defaultOrganization", defaultOrganization) }
    }

    public var notificationSoundID: String {
        didSet { debouncedSave("notificationSoundID", notificationSoundID) }
    }
    public var messageSoundID: String {
        didSet { debouncedSave("messageSoundID", messageSoundID) }
    }
    public var successSoundID: String {
        didSet { debouncedSave("successSoundID", successSoundID) }
    }
    public var errorSoundID: String {
        didSet { debouncedSave("errorSoundID", errorSoundID) }
    }
    public var completionSoundID: String {
        didSet { debouncedSave("completionSoundID", completionSoundID) }
    }

    public var useNewSettingsWindow: Bool {
        didSet {
            debouncedSave("useNewSettingsWindow", useNewSettingsWindow)
            UserDefaults.standard.set(useNewSettingsWindow, forKey: "useNewSettingsWindow")
            NotificationCenter.default.post(name: NSNotification.Name("UseNewSettingsWindowDidChange"), object: useNewSettingsWindow)
        }
    }

    private func debouncedSave(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.synchronize()
    }

    public func persistAllSettings() {
        UserDefaults.standard.synchronize()
    }

    public var isUsingCustomModel: Bool {
        !customModel.isEmpty && selectedModel == customModel
    }

    private init() {
        assistSystemID = UserDefaults.standard.string(forKey: "assistSystemID") ?? Self.nativeAssistSystemID
        var initialToolkit = UserDefaults.standard.string(forKey: "assistToolkit")
            ?? UserDefaults.standard.string(forKey: "assist.assistToolkit")
            ?? Self.defaultAssistToolkit
        if initialToolkit.caseInsensitiveCompare("cloud") == .orderedSame {
            initialToolkit = "Provider"
            UserDefaults.standard.set("Provider", forKey: "assist.assistToolkit")
            UserDefaults.standard.set("Provider", forKey: "assistToolkit")
        }
        assistToolkit = initialToolkit
        assistAutomaticallySwitchModels = UserDefaults.standard.object(forKey: "assist.automaticallySwitchModels") as? Bool ?? true
        assistUseProviderModels = UserDefaults.standard.object(forKey: "assist.useProviderModels") as? Bool ?? false
        metaAssistModelID = UserDefaults.standard.string(forKey: "metaAssistModelID")
            ?? UserDefaults.standard.string(forKey: "assist.metaAssistModelID")
            ?? Self.defaultMetaAssistModelID
        metaReasoningEffort = UserDefaults.standard.string(forKey: "metaReasoningEffort")
            ?? UserDefaults.standard.string(forKey: "assist.metaReasoningEffort")
            ?? Self.defaultMetaReasoningEffort
        otherModelsWithMetaSDK = UserDefaults.standard.object(forKey: "otherModelsWithMetaSDK") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.otherModelsWithMetaSDK") as? Bool
            ?? false
        swiftCodeCloudWithMetaSDK = UserDefaults.standard.object(forKey: "swiftCodeCloudWithMetaSDK") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.swiftCodeCloudWithMetaSDK") as? Bool
            ?? false
        useOtherModelsWhenRateLimited = UserDefaults.standard.object(forKey: "useOtherModelsWhenRateLimited") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.useOtherModelsWhenRateLimited") as? Bool
            ?? true
        metaSelectedOtherModelID = UserDefaults.standard.string(forKey: "metaSelectedOtherModelID")
            ?? UserDefaults.standard.string(forKey: "assist.metaSelectedOtherModelID")
            ?? ""
        metaSelectedOtherModelProvider = UserDefaults.standard.string(forKey: "metaSelectedOtherModelProvider")
            ?? UserDefaults.standard.string(forKey: "assist.metaSelectedOtherModelProvider")
            ?? ""
        useMetaSlashCommands = UserDefaults.standard.object(forKey: "useMetaSlashCommands") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.useMetaSlashCommands") as? Bool
            ?? true
        reverseEnabled = UserDefaults.standard.object(forKey: "assist.reverseEnabled") as? Bool ?? true
        reverseBridgePath = UserDefaults.standard.string(forKey: "assist.reverseBridgePath") ?? ""
        reverseReaDir = UserDefaults.standard.string(forKey: "assist.reverseReaDir") ?? ""
        enableUserMemory = UserDefaults.standard.object(forKey: "enableUserMemory") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.enableUserMemory") as? Bool
            ?? true
        onlyUseFreeModels = UserDefaults.standard.object(forKey: "onlyUseFreeModels") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.onlyUseFreeModels") as? Bool
            ?? false
        swiftCloudModelsEnabled = UserDefaults.standard.object(forKey: "swiftCloudModelsEnabled") as? Bool ?? false
        let loadedUseSavedModels = UserDefaults.standard.object(forKey: "useSavedModels") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.useSavedModels") as? Bool
            ?? false
        let loadedAlternativeKeysEnabled = UserDefaults.standard.object(forKey: "alternativeKeysEnabled") as? Bool
            ?? UserDefaults.standard.object(forKey: "assist.alternativeKeysEnabled") as? Bool
            ?? false
        self.useSavedModels = loadedUseSavedModels
        self.alternativeKeysEnabled = loadedAlternativeKeysEnabled

        if let savedStrategy = UserDefaults.standard.string(forKey: "assist.modelRoutingStrategy") {
            assistModelRoutingStrategy = savedStrategy
        } else if loadedAlternativeKeysEnabled {
            assistModelRoutingStrategy = "rotation"
        } else if loadedUseSavedModels {
            assistModelRoutingStrategy = "app_models"
        } else {
            assistModelRoutingStrategy = "default"
        }
        assistGoogleAuthMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? "google_oauth"
        useSwiftCodeCloudModel = UserDefaults.standard.bool(forKey: "assist.useSwiftCodeCloudModel")
        assistGoogleCloudProject = UserDefaults.standard.string(forKey: "assist_google_cloud_project") ?? ""
        assistGoogleOAuthClientIDOverride = UserDefaults.standard.string(forKey: "assist_google_oauth_client_id_override") ?? ""
        antigravityExecutionMode = UserDefaults.standard.string(forKey: "antigravity_execution_mode") ?? "bridge"
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "openai/gpt-4o"
        customModel   = UserDefaults.standard.string(forKey: "customModel") ?? ""
        customModelProviderID = UserDefaults.standard.string(forKey: "assist_custom_model_provider_id") ?? "google"
        selectedAssistModelID = UserDefaults.standard.string(forKey: "selectedAssistModelID") ?? ""
        autoSave = UserDefaults.standard.object(forKey: "autoSave") as? Bool ?? true
        editorFontSize = UserDefaults.standard.object(forKey: "editorFontSize") as? Double ?? 14
        useDarkTheme = UserDefaults.standard.object(forKey: "useDarkTheme") as? Bool ?? true
        fileHeaderAuthor = UserDefaults.standard.string(forKey: "fileHeaderAuthor") ?? ""
        fileHeaderCustomComment = UserDefaults.standard.string(forKey: "fileHeaderCustomComment") ?? "Made with SwiftCode"
        selectedThemeID = UserDefaults.standard.string(forKey: "selectedThemeID") ?? "dark"
        gitPath = UserDefaults.standard.string(forKey: "gitPath") ?? ""
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
        saveProjectsOnCustomFolder = UserDefaults.standard.object(forKey: "saveProjectsOnCustomFolder") as? Bool ?? false
        customProjectsFolder = UserDefaults.standard.string(forKey: "customProjectsFolder") ?? ""
        defaultOrganization = UserDefaults.standard.string(forKey: "defaultOrganization") ?? "com.SwiftCode"
        useNewSettingsWindow = UserDefaults.standard.object(forKey: "useNewSettingsWindow") as? Bool ?? true

        let rawNotif = UserDefaults.standard.string(forKey: "notificationSoundID") ?? "custom.chill.soft_bloom"
        notificationSoundID = (rawNotif == "none" || Self.isKnownSoundID(rawNotif)) ? rawNotif : "custom.chill.soft_bloom"

        let rawMsg = UserDefaults.standard.string(forKey: "messageSoundID") ?? "custom.message.message"
        messageSoundID = (rawMsg == "none" || Self.isKnownSoundID(rawMsg)) ? rawMsg : "custom.message.message"

        let rawSuccess = UserDefaults.standard.string(forKey: "successSoundID") ?? "custom.success.complete"
        successSoundID = (rawSuccess == "none" || Self.isKnownSoundID(rawSuccess)) ? rawSuccess : "custom.success.complete"

        let rawError = UserDefaults.standard.string(forKey: "errorSoundID") ?? "custom.error.attention"
        errorSoundID = (rawError == "none" || Self.isKnownSoundID(rawError)) ? rawError : "custom.error.attention"

        let rawComplete = UserDefaults.standard.string(forKey: "completionSoundID") ?? "custom.success.complete"
        completionSoundID = (rawComplete == "none" || Self.isKnownSoundID(rawComplete)) ? rawComplete : "custom.success.complete"

        loadSavedRepositories()

        validateCurrentSelectionsForEligibility()
    }

    public func validateCurrentSelectionsForEligibility() {
        guard onlyUseFreeModels else { return }

        if !metaSelectedOtherModelID.isEmpty && !AssistModelEligibilityPolicy.isEligible(modelID: metaSelectedOtherModelID, onlyUseFreeModels: true) {
            metaSelectedOtherModelID = ""
            metaSelectedOtherModelProvider = ""
        }

        if !selectedAssistModelID.isEmpty && !AssistModelEligibilityPolicy.isEligible(modelID: selectedAssistModelID, onlyUseFreeModels: true) {
            selectedAssistModelID = ""
        }
    }

    private static let savedReposKey = "savedRepositories"

    private func persistSavedRepositories() {
        if let data = try? JSONEncoder().encode(savedRepositories) {
            UserDefaults.standard.set(data, forKey: Self.savedReposKey)
            UserDefaults.standard.synchronize()
        }
    }

    private func loadSavedRepositories() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedReposKey),
              let decoded = try? JSONDecoder().decode([SavedRepository].self, from: data) else { return }
        savedRepositories = decoded
    }

    public func addRepository(_ repo: SavedRepository) {
        savedRepositories.append(repo)
    }

    public func removeRepository(_ repo: SavedRepository) {
        savedRepositories.removeAll { $0.id == repo.id }
    }
}
