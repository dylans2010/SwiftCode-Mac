import Foundation

@MainActor
final class OnDeviceModelRouter {
    static let shared = OnDeviceModelRouter()
    private init() {}

    func useOnDeviceAI() -> Bool {
        UserDefaults.standard.bool(forKey: "appleIntelligenceEnabled") && DeviceUtilityManager.shared.isAppleIntelligenceSupported()
    }

    func generateResponse(prompt: String, useContext: Bool) async throws -> String {
        if useOnDeviceAI() {
            return try await OnDeviceAIManager.shared.sendPrompt(useContext ? "[Context Aware]\n\n\(prompt)" : prompt)
        }
        return try await LLMService.shared.generateExternalResponse(prompt: prompt, useContext: useContext)
    }
}
