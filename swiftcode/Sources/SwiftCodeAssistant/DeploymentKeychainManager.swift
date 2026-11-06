// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Deployments/DeploymentKeychainManager.swift
//   (Legacy main ab03f681) — verbatim, no adaptations (internal, as Legacy).
//   Staged by migration subagent F2 (unowned-dependency triage) — NOT yet
//   landed in the repo.
//
// Destination: SwiftCodeAssistant/DeploymentKeychainManager.swift.
//
// Dependency: `KeychainService` (staged in this same batch). Used by
// `APIKeyManager` (staged in this same batch) for the GitHub/Netlify/
// Vercel sync paths.

import Foundation

final class DeploymentKeychainManager: Sendable {
    static let shared = DeploymentKeychainManager()
    private init() {}

    enum Service: String {
        case netlify = "netlify_api_token"
        case vercel = "vercel_api_token"
        case github = "github_personal_access_token"
    }

    func storeKey(service: Service, key: String) {
        KeychainService.shared.set(key, forKey: service.rawValue)
    }

    func retrieveKey(service: Service) -> String? {
        return KeychainService.shared.get(forKey: service.rawValue)
    }

    func deleteKey(service: Service) {
        KeychainService.shared.delete(forKey: service.rawValue)
    }
}
