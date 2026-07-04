import Foundation
import Observation

@Observable
@MainActor
public class SettingsViewModel {
    public var openRouterKey: String = ""
    public var githubPAT: String = ""
    public var selectedModel: String = "openai/gpt-4o"
    public var availableModels: [OpenRouterModel] = []

    public var customAIEndpoint: String = ""
    public var customAIHeaders: String = ""
    public var customAIKey: String = ""
    public var useCustomAI: Bool = false

    public init() {
        Task {
            openRouterKey = try? await KeychainService.shared.get(account: "openrouter-api-key") ?? ""
            githubPAT = try? await KeychainService.shared.get(account: "github-pat") ?? ""
            selectedModel = await PreferencesStore.shared.get(forKey: "selected_ai_model") as? String ?? "openai/gpt-4o"
            customAIEndpoint = await PreferencesStore.shared.get(forKey: "custom_ai_endpoint") as? String ?? ""
            customAIHeaders = await PreferencesStore.shared.get(forKey: "custom_ai_headers") as? String ?? ""
            useCustomAI = await PreferencesStore.shared.get(forKey: "use_custom_ai") as? Bool ?? false

            if !openRouterKey.isEmpty {
                await fetchAvailableModels()
            }
        }
    }

    public func fetchAvailableModels() async {
        do {
            availableModels = try await OpenRouterClient.shared.fetchModels()
        } catch {
            print("Failed to fetch models: \(error)")
        }
    }

    public func saveSettings() async {
        try? await KeychainService.shared.save(account: "openrouter-api-key", value: openRouterKey)
        try? await KeychainService.shared.save(account: "github-pat", value: githubPAT)
        await PreferencesStore.shared.set(selectedModel, forKey: "selected_ai_model")
        await PreferencesStore.shared.set(customAIEndpoint, forKey: "custom_ai_endpoint")
        await PreferencesStore.shared.set(customAIHeaders, forKey: "custom_ai_headers")
        await PreferencesStore.shared.set(useCustomAI, forKey: "use_custom_ai")

        if !customAIKey.isEmpty {
             try? await KeychainService.shared.save(account: "custom-ai-key", value: customAIKey)
        }
    }

    public func clearCache() {
        // Implementation for clearing caches
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let url = cacheURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
