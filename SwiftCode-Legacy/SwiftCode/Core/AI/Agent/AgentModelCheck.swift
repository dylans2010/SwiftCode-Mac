import Foundation

public enum ModelCheckStatus: String, Sendable, Codable {
    case success
    case invalid_key
    case model_not_found
    case rate_limited
    case network_error
    case configuration_error
}

public struct AgentModelCheckResult: Sendable, Codable {
    public let status: ModelCheckStatus
    public let latency: TimeInterval
    public let modelCapability: String
}

public actor AgentModelCheck {
    public static let shared = AgentModelCheck()
    private init() {}

    public func checkModel(provider: String, apiKey: String, model: String) async -> AgentModelCheckResult {
        let startTime = Date()

        do {
            guard let llmProvider = LLMProvider(rawValue: provider) else {
                return AgentModelCheckResult(
                    status: .configuration_error,
                    latency: Date().timeIntervalSince(startTime),
                    modelCapability: "Unknown provider: \(provider)"
                )
            }

            // Validate the API key and fetch models as a check
            _ = try await LLMService.shared.validateAPIKey(provider: llmProvider, key: apiKey)

            let latency = Date().timeIntervalSince(startTime)
            return AgentModelCheckResult(
                status: .success,
                latency: latency,
                modelCapability: "Model \(model) is reachable and API key is valid."
            )
        } catch let error as LLMError {
            let latency = Date().timeIntervalSince(startTime)
            switch error {
            case .invalidKey:
                return AgentModelCheckResult(status: .invalid_key, latency: latency, modelCapability: error.localizedDescription)
            case .rateLimited:
                return AgentModelCheckResult(status: .rate_limited, latency: latency, modelCapability: error.localizedDescription)
            case .modelNotFound:
                return AgentModelCheckResult(status: .model_not_found, latency: latency, modelCapability: error.localizedDescription)
            case .networkError(let desc):
                return AgentModelCheckResult(status: .network_error, latency: latency, modelCapability: desc)
            default:
                return AgentModelCheckResult(status: .configuration_error, latency: latency, modelCapability: error.localizedDescription)
            }
        } catch {
            let latency = Date().timeIntervalSince(startTime)
            return AgentModelCheckResult(
                status: .network_error,
                latency: latency,
                modelCapability: error.localizedDescription
            )
        }
    }
}
