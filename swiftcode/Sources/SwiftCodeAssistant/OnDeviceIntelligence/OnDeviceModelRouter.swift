// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/On Device Intelligence/OnDeviceModelRouter.swift
//   (Legacy commit d51a8f0d)
//
// GAP — Legacy's fallback has no destination equivalent. When
// on-device AI was off, Legacy called
// `LLMService.shared.generateExternalResponse(prompt:useContext:)` —
// its cloud LLM facade. No `LLMService` exists in the destination:
// the destination's providers are reached through `AssistantProvider`
// (`FoundationModelsProvider`, `OpenAIProvider`, …) with their own
// credentials and selection, and there is no single "generate
// externally" entry point to call. Rather than build a parallel
// manager or silently reroute cloud traffic to the on-device model,
// `generateResponse` throws `OnDeviceRouterError.externalServiceUnavailable`
// when on-device AI is off, naming the gap. Callers that need a
// cloud reply should drive an `AssistantProvider` directly. The
// on-device branch (Legacy's `useOnDeviceAI` check + `OnDeviceAIManager`)
// is ported as-is, including Legacy's `appleIntelligenceEnabled`
// UserDefaults key.

import Foundation

public enum OnDeviceRouterError: LocalizedError, Sendable {
    /// On-device AI is off and there is no external LLM service to fall
    /// back to in this target (Legacy's `LLMService` was not ported).
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
