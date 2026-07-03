import Foundation
import Observation

@Observable
@MainActor
public class SettingsViewModel {
    public var openRouterKey: String = ""
    public var githubPAT: String = ""

    public init() {
        Task {
            openRouterKey = try? await KeychainService.shared.get(account: "openrouter-api-key") ?? ""
            githubPAT = try? await KeychainService.shared.get(account: "github-pat") ?? ""
        }
    }

    public func saveKeys() async {
        try? await KeychainService.shared.save(account: "openrouter-api-key", value: openRouterKey)
        try? await KeychainService.shared.save(account: "github-pat", value: githubPAT)
    }
}
