import Foundation

public enum OnDeviceRouterError: LocalizedError, Sendable {
    case externalServiceUnavailable

    public var errorDescription: String? {
        switch self {
        case .externalServiceUnavailable:
            return "On-device AI is off and no external language-model service is available in this target. Legacy fell back to LLMService, which has no SwiftCode equivalent; use an AssistantProvider directly for a cloud reply."
        }
    }
}

@MainActor
public final class OnDeviceModelRouter {
    public static let shared = OnDeviceModelRouter()
    private init() {}

    public func useOnDeviceAI() -> Bool {
        UserDefaults.standard.bool(forKey: "appleIntelligenceEnabled") && DeviceUtilityManager.shared.isAppleIntelligenceSupported()
    }

    public func generateResponse(prompt: String, useContext: Bool) async throws -> String {
        if useOnDeviceAI() {
            return try await OnDeviceAIManager.shared.sendPrompt(useContext ? "[Context Aware]\n\n\(prompt)" : prompt)
        }
        throw OnDeviceRouterError.externalServiceUnavailable
    }
}
