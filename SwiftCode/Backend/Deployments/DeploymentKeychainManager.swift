import Foundation

final class DeploymentKeychainManager {
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
