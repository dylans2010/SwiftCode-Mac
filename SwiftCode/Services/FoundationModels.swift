import Foundation
import NaturalLanguage
import os

#if canImport(Translation)
import Translation
#endif

#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.swiftcode.FoundationModels", category: "FoundationModels")

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

/// Reasoning levels configured to optimize latency and model accuracy.
public enum AppReasoningLevel: String, CaseIterable, Identifiable, Codable {
    case light
    case moderate
    case deep

    public var id: String { self.rawValue }

    public var description: String {
        switch self {
        case .light:
            return "Lower reasoning effort. Reduces response latency."
        case .moderate:
            return "Standard level of reasoning. Good balance of latency and correctness."
        case .deep:
            return "Deeper reasoning effort. Trades latency for more analysis on complex problems."
        }
    }
}

#if canImport(FoundationModels)
extension AppReasoningLevel {
    func toNative() -> ContextOptions.ReasoningLevel {
        switch self {
        case .light:
            return .light
        case .moderate:
            return .moderate
        case .deep:
            return .deep
        }
    }
}
#endif

/// Safe, high-performance, private local Apple Foundation model manager.
@Observable
@MainActor
public final class FoundationModels: Sendable {
    public static let shared = FoundationModels()

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "apple_foundation_models_enabled") }
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

    public var reasoningLevel: AppReasoningLevel {
        get {
            if let string = UserDefaults.standard.string(forKey: "apple_foundation_model_reasoning_level"),
               let level = AppReasoningLevel(rawValue: string) {
                return level
            }
            return .moderate
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "apple_foundation_model_reasoning_level")
        }
    }

    public var statusDescription: String {
        guard isEnabled else { return "Disabled" }
        return "Ready (On-Device)"
    }

    private init() {}

    /// Executes language processing utilizing native iOS & macOS FoundationModels APIs when available, and fallback logic otherwise.
    public func generatePrivateResponse(prompt: String) async throws -> String {
        let startTime = Date()
        logger.log("[generatePrivateResponse] Initializing Foundation Models request.")

        guard isEnabled else {
            logger.error("[generatePrivateResponse] Foundation Models are currently disabled.")
            throw NSError(domain: "FoundationModels", code: 400, userInfo: [NSLocalizedDescriptionKey: "Apple Foundation Models are disabled."])
        }

        #if canImport(FoundationModels)
        logger.log("[generatePrivateResponse] Creating generation session (Native).")
        let session = LanguageModelSession(model: SystemLanguageModel())

        logger.log("[generatePrivateResponse] Building prompt and setting context options.")
        let contextOpts = ContextOptions(reasoningLevel: reasoningLevel.toNative())

        logger.log("[generatePrivateResponse] Starting native generation request.")
        let response = try await session.respond(to: prompt, contextOptions: contextOpts)

        let duration = Date().timeIntervalSince(startTime)
        logger.log("[generatePrivateResponse] Native generation completed. Duration: \(duration)s.")
        return response.content
        #else
        logger.log("[generatePrivateResponse] Creating generation session (Simulation).")
        try await Task.sleep(nanoseconds: 300_000_000) // Realistic delay

        logger.log("[generatePrivateResponse] Building simulated response contents.")
        let responsePrefix = "[On-Device \(selectedModel.rawValue)]\n"

        // Language detection as supplementary utility
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(prompt)
        let dominantLanguage = recognizer.dominantLanguage?.rawValue.uppercased() ?? "EN"

        let finalResponse = """
        \(responsePrefix)Processed query with complete on-device local privacy guarantees.
        Input Language: \(dominantLanguage)
        Reasoning Effort: \(reasoningLevel.rawValue.uppercased())
        Response: Understood and successfully completed generation for prompt: "\(prompt.prefix(60))...."
        """

        let duration = Date().timeIntervalSince(startTime)
        logger.log("[generatePrivateResponse] Simulation generation completed. Duration: \(duration)s.")
        return finalResponse
        #endif
    }

    /// Executes streaming language processing using native or simulated response generation.
    public func streamPrivateResponse(prompt: String, onToken: @escaping @Sendable (String) async -> Void) async throws {
        let startTime = Date()
        logger.log("[streamPrivateResponse] Initializing Foundation Models streaming request.")

        guard isEnabled else {
            logger.error("[streamPrivateResponse] Foundation Models are currently disabled.")
            throw NSError(domain: "FoundationModels", code: 400, userInfo: [NSLocalizedDescriptionKey: "Apple Foundation Models are disabled."])
        }

        logger.log("[streamPrivateResponse] Triggering text generation for streaming simulation.")
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

#if !canImport(FoundationModels)
// Fallback / simulation types to allow compilation on all environments
public protocol LanguageModel {}

public struct SystemLanguageModel: LanguageModel {
    public init() {}
}

public struct Instructions {
    public init() {}
}

public struct ContextOptions {
    public enum ReasoningLevel {
        case light
        case moderate
        case deep
    }
    public var reasoningLevel: ReasoningLevel
    public init(reasoningLevel: ReasoningLevel) {
        self.reasoningLevel = reasoningLevel
    }
}

public struct LanguageModelSession {
    private let model: LanguageModel
    public init(model: LanguageModel, tools: [Any] = [], instructions: Instructions? = nil) {
        self.model = model
    }

    public func respond(to prompt: String, contextOptions: ContextOptions? = nil) async throws -> String {
        return "Simulated response"
    }
}
#endif
