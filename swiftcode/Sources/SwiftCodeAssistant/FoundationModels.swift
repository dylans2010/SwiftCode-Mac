import Foundation
import os

// Ported from Legacy `SwiftCode/Services/FoundationModels.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Landed verbatim by a parallel agent; adapted by fix W-V2 (A6 slice: LLMService,
// OpenRouterService and AgentModelAdapter all use FoundationModels.shared).
//
// DECISION (A4 cleanup pass, 2026-11-06) — simulation fallback DELETED, honest
// unavailable instead. Legacy's `#else` branch fabricated model output when the
// Apple FoundationModels framework was unavailable (Linux / older macOS): canned
// titles, prompt-enhancement JSON, and "[On-Device …] Processed query …" replies
// presented as if a model had answered. That is gone. The real path is the
// `#if canImport(FoundationModels)` + `#available(macOS 26.0, iOS 26.0, *)` +
// `SystemLanguageModel.default.availability` gate — the same live check
// `FoundationModelsProvider` and `DeviceUtilityManager.getCapabilityLevel()`
// use. Where the framework is absent, the OS is below macOS 26, or the system
// model is unavailable (Apple Intelligence off, model still downloading,
// device not eligible), `generatePrivateResponse` / `streamPrivateResponse`
// throw `FoundationModelsError.unavailable` with the real reason. Callers
// already handle that honestly: `LLMService`'s stage chain falls through to
// real providers (OpenRouter/Google/OpenAI/Anthropic), `CodingToolsService`
// falls back to `AgentModelAdapter`, `AssistConversationHistory` falls back
// to the local title heuristic, and `AgentModelAdapter.handleFallbackQuery`
// rethrows. Nothing here fabricates model output any more.
// `generateConciseTitle` is KEPT: it is a deterministic local string
// transform over real input text (a title heuristic), not model output.
// `selectedModel` is display-only: the framework exposes one system model
// and no API to select AFM 3 Core Advanced (see `FoundationModelsProvider`);
// the session is always built from `SystemLanguageModel.default`.
// `statusDescription` is now gated on the same live availability check
// instead of unconditionally reporting "Ready (On-Device)".

#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.swiftcode.FoundationModels", category: "FoundationModels")

/// Thrown instead of fabricating a model reply when Apple Foundation
/// Models cannot run here: framework absent (Linux / older SDK), OS
/// below macOS 26, or the system model unavailable (Apple Intelligence
/// off, model still downloading, device not eligible). Callers catch
/// this and fall back to a real provider or surface the error.
public enum FoundationModelsError: Error, LocalizedError {
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

/// Property wrapper to annotate structures or services that use text generation capabilities
@propertyWrapper
public struct Generable<T>: Sendable where T: Sendable {
    public var wrappedValue: T
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}

/// The core Apple Foundation Models from the AFM 3 family.
public enum AppleFoundationModel: String, CaseIterable, Identifiable, Codable {
    case afm3Core = "AFM 3 Core"
    case afm3CoreAdvanced = "AFM 3 Core Advanced"

    public var id: String { self.rawValue }

    public var description: String {
        switch self {
        case .afm3Core:
            return "On-device 3-billion-parameter dense model for responsive everyday tasks."
        case .afm3CoreAdvanced:
            return "On-device 20-billion-parameter sparse model (natively multimodal, expressive voice/dictation)."
        }
    }
}

/// Safe, high-performance, private local Apple Foundation model manager.
@Observable
@MainActor
public final class FoundationModels: Sendable {
    public static let shared = FoundationModels()

    public var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "apple_foundation_models_enabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "apple_foundation_models_enabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "apple_foundation_models_enabled") }
    }

    public var selectedModel: AppleFoundationModel {
        get {
            if let string = UserDefaults.standard.string(forKey: "apple_foundation_model_selected"),
               let model = AppleFoundationModel(rawValue: string) {
                return model
            }
            return .afm3Core
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "apple_foundation_model_selected")
        }
    }

    /// Whether the real on-device model can run right now: the framework
    /// must be present, the OS new enough, and the system model available
    /// (Apple Intelligence on, model downloaded, device eligible) — the
    /// same live check `FoundationModelsProvider` / `DeviceUtilityManager`
    /// use. `false` on Linux / older macOS, where there is no model at all.
    public var isAvailable: Bool {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
#endif
        return false
    }

    public var statusDescription: String {
        guard isEnabled else { return "Disabled" }
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Ready (On-Device)"
            case .unavailable(let reason):
                return Self.unavailableMessage(for: reason)
            @unknown default:
                return "Apple Foundation Models is unavailable on this device."
            }
        }
        return "Unavailable — needs macOS 26 or later"
#else
        return "Unavailable — Apple Foundation Models is not available on this system"
#endif
    }

    /// Hint shown / thrown where the framework cannot be used at all.
    static let unavailableHint = "Apple Foundation Models is not available on this device. It needs macOS 26 or later on an Apple Intelligence-capable Mac, with Apple Intelligence turned on."

    /// Human-readable reason the system model cannot run, mirroring
    /// `FoundationModelsProvider.unavailableMessage(for:)` (matched one
    /// case at a time so an unfamiliar reason still yields an honest
    /// message instead of a compile break on a future OS).
#if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private static func unavailableMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        if case .appleIntelligenceNotEnabled = reason {
            return "Apple Intelligence is turned off. Turn it on in System Settings to use Apple Foundation Models."
        }
        if case .modelNotReady = reason {
            return "The Apple Foundation Models on-device model is still downloading. Try again later."
        }
        if case .deviceNotEligible = reason {
            return "This device cannot run Apple Foundation Models. It needs an Apple Intelligence-capable Mac."
        }
        return "Apple Foundation Models is unavailable on this device."
    }
#endif

    private init() {}

    /// Executes language processing with the native iOS & macOS
    /// FoundationModels APIs. Throws `FoundationModelsError.unavailable`
    /// (never a fabricated reply) when the framework or the system model
    /// is unavailable on this device.
    public func generatePrivateResponse(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let startTime = Date()
        logger.log("[generatePrivateResponse] Initializing Foundation Models request.")

        guard isEnabled else {
            logger.error("[generatePrivateResponse] Foundation Models are currently disabled.")
            throw NSError(domain: "FoundationModels", code: 400, userInfo: [NSLocalizedDescriptionKey: "Apple Foundation Models are disabled."])
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                if case .unavailable(let reason) = SystemLanguageModel.default.availability {
                    throw FoundationModelsError.unavailable(Self.unavailableMessage(for: reason))
                }
                throw FoundationModelsError.unavailable(Self.unavailableHint)
            }
            logger.log("[generatePrivateResponse] Creating generation session (Native).")
            let instructions: Instructions? = systemPrompt.map { Instructions($0) }
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)

            logger.log("[generatePrivateResponse] Starting native generation request.")
            let response = try await session.respond(to: prompt)

            let duration = Date().timeIntervalSince(startTime)
            logger.log("[generatePrivateResponse] Native generation completed. Duration: \(duration)s.")
            return response.content
        } else {
            throw FoundationModelsError.unavailable("Apple Foundation Models needs macOS 26 or later.")
        }
        #else
        throw FoundationModelsError.unavailable(Self.unavailableHint)
        #endif
    }

    /// Generates a clean, concise title under 25 characters from prompt text.
    /// A deterministic local string transform over real input text — not
    /// model output. `AssistConversationHistory` uses it as the title
    /// heuristic when the on-device model is unavailable.
    public static func generateConciseTitle(from raw: String) -> String {
        var text = raw.replacingOccurrences(of: "```[a-zA-Z]*\n[\\s\\S]*?```", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "@[A-Za-z0-9_]+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\n", with: " ")

        let prefixesToRemove = [
            "can you please help me with", "could you please help me with",
            "can you please", "could you please", "please help me with",
            "i want to", "i need to", "how do i", "can you", "help me with",
            "please", "write a", "create a", "implement a", "fix the", "explain how",
            "how to", "make the", "suggest a", "build a", "add a", "update the"
        ]
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        for prefix in prefixesToRemove {
            if lower.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let words = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var resultWords: [String] = []
        var totalLength = 0

        for word in words {
            let cap = word.prefix(1).uppercased() + word.dropFirst()
            let nextLength = totalLength + (resultWords.isEmpty ? 0 : 1) + cap.count
            if nextLength <= 24 && resultWords.count < 4 {
                resultWords.append(cap)
                totalLength = nextLength
            } else {
                break
            }
        }

        let title = resultWords.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?-"))
        if title.isEmpty {
            return "Swift Coding Task"
        }
        return String(title.prefix(24))
    }

    /// Executes streaming language processing using the native on-device
    /// session. The response itself always comes from the real model:
    /// `generatePrivateResponse` throws when it is unavailable, so no
    /// token is ever emitted from fabricated text — the word-by-word
    /// delivery below is only pacing of the real reply.
    public func streamPrivateResponse(prompt: String, onToken: @escaping @Sendable (String) async -> Void) async throws {
        let startTime = Date()
        logger.log("[streamPrivateResponse] Initializing Foundation Models streaming request.")

        guard isEnabled else {
            logger.error("[streamPrivateResponse] Foundation Models are currently disabled.")
            throw NSError(domain: "FoundationModels", code: 400, userInfo: [NSLocalizedDescriptionKey: "Apple Foundation Models are disabled."])
        }

        logger.log("[streamPrivateResponse] Triggering text generation for streaming.")
        let fullResponse = try await generatePrivateResponse(prompt: prompt)

        logger.log("[streamPrivateResponse] Starting token streaming delivery.")
        let words = fullResponse.split(separator: " ", omittingEmptySubsequences: false).map { String($0) }
        for (index, word) in words.enumerated() {
            // Check for task cancellation
            if Task.isCancelled {
                logger.log("[streamPrivateResponse] Task cancellation detected. Stopping stream.")
                break
            }

            let token = word + (index == words.count - 1 ? "" : " ")
            try await Task.sleep(nanoseconds: 30_000_000) // 30ms delay
            await onToken(token)
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.log("[streamPrivateResponse] Token streaming completed successfully. Total duration: \(duration)s.")
    }
}
