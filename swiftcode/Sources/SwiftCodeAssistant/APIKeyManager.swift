// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Settings/GeneralSettingsView.swift (lines 1–280 only)
//   (Legacy main ab03f681) — `APIKeyProvider`, `APIKeyEntry`, `APIKeyManager`.
//   The rest of that 3,494-line view file is NOT staged here (view scope,
//   owned by the views worklist); only the key-manager types it declares.
//
// Destination: SwiftCodeAssistant/APIKeyManager.swift.
//
// Adaptations (behaviour preserved unless noted):
// * `APIKeyProvider` / `APIKeyEntry` / `APIKeyManager` were internal in
//   Legacy; made `public` — live main code calls them across modules
//   (`AssistSettingsView` reads/stores OpenRouter/OpenAI/Anthropic/Gemini
//   keys; `AssistModelProvider.storedAPIKey()` in this same batch calls
//   `retrieveKey`).
// * `import SwiftUI` NOT carried over: Legacy's `APIKeyProvider.tintColor`
//   (a `Color`) has no callers in production and SwiftCodeAssistant must
//   stay SwiftUI-free / Linux-buildable. If settings UI needs per-provider
//   tints later, the mapping belongs in SwiftCodeUI, not here.
//   `import Observation` added: `APIKeyManager` is `@Observable`.
// * `import StoreKit` dropped: nothing in the extracted types uses it.
// * Dependencies, all present: `KeychainService` (staged in this same
//   batch), `DeploymentKeychainManager` (staged in this same batch),
//   `AppSettings.shared.httpsAuthToken` (on main,
//   `SwiftCodeAssistant/AppSettings.swift:507`).

import Foundation
import Observation

// MARK: - API Key Models

public enum APIKeyProvider: String, Codable, CaseIterable {
    case openRouter = "OpenRouter"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Gemini"
    case mistral = "Mistral"
    case qwen = "Qwen"
    case gitHub = "GitHub"
    case netlify = "Netlify"
    case vercel = "Vercel"

    public var icon: String {
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
}

public struct APIKeyEntry: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var provider: APIKeyProvider

    public var keychainKey: String { "api_key_entry_\(id.uuidString)" }

    public init(id: UUID = UUID(), name: String, provider: APIKeyProvider) {
        self.id = id
        self.name = name
        self.provider = provider
    }
}

// MARK: - API Key Manager

@Observable
@MainActor
public final class APIKeyManager {
    public static let shared = APIKeyManager()

    public var keys: [APIKeyEntry] = [] {
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

    public func add(name: String, provider: APIKeyProvider, keyValue: String) {
        if providerKeyExists(service: provider) { return }
        let entry = APIKeyEntry(name: name, provider: provider)
        KeychainService.shared.set(keyValue, forKey: entry.keychainKey)
        keys.append(entry)
        syncKey(entry, value: keyValue)
    }

    public func update(_ entry: APIKeyEntry, keyValue: String) {
        KeychainService.shared.set(keyValue, forKey: entry.keychainKey)
        syncKey(entry, value: keyValue)
    }

    public func delete(_ entry: APIKeyEntry) {
        KeychainService.shared.delete(forKey: entry.keychainKey)
        keys.removeAll { $0.id == entry.id }
        clearSyncedKey(for: entry.provider)
    }

    public func keyValue(for entry: APIKeyEntry) -> String? {
        KeychainService.shared.get(forKey: entry.keychainKey)
    }

    // MARK: - Keychain Methods

    public func storeKey(service: APIKeyProvider, key: String) {
        // Find existing entry or create new
        if let idx = keys.firstIndex(where: { $0.provider == service }) {
            update(keys[idx], keyValue: key)
        } else {
            add(name: "\(service.rawValue) Key", provider: service, keyValue: key)
        }
    }

    public func retrieveKey(service: APIKeyProvider) -> String? {
        if let entry = keys.first(where: { $0.provider == service }) {
            return keyValue(for: entry)
        }
        return nil
    }

    public func deleteKey(service: APIKeyProvider) {
        if let entry = keys.first(where: { $0.provider == service }) {
            delete(entry)
        }
    }

    public func providerKeyExists(service: APIKeyProvider) -> Bool {
        keys.contains { $0.provider == service }
    }

    private func syncKey(_ entry: APIKeyEntry, value: String) {
        switch entry.provider {
        case .openRouter:
            KeychainService.shared.set(value, forKey: KeychainService.openRouterAPIKey)
            KeychainService.shared.set(value, forKey: "openrouter-api-key")
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
            KeychainService.shared.set(value, forKey: KeychainService.githubToken)
            AppSettings.shared.httpsAuthToken = value
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
            KeychainService.shared.delete(forKey: "openrouter-api-key")
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

    public func reset() {
        for key in keys { KeychainService.shared.delete(forKey: key.keychainKey) }
        keys = []
    }
}
