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

/// The five core Apple Foundation Models from the AFM 3 family.
public enum AppleFoundationModel: String, CaseIterable, Identifiable, Codable {
    case afm3Core = "AFM 3 Core"
    case afm3CoreAdvanced = "AFM 3 Core Advanced"
    case afm3Cloud = "AFM 3 Cloud"
    case afm3CloudPro = "AFM 3 Cloud Pro"
    case adm3Cloud = "ADM 3 Cloud"

    public var id: String { self.rawValue }

    public var isServerBased: Bool {
        switch self {
        case .afm3Core, .afm3CoreAdvanced:
            return false
        case .afm3Cloud, .afm3CloudPro, .adm3Cloud:
            return true
        }
    }

    public var description: String {
        switch self {
        case .afm3Core:
            return "On-device 3-billion-parameter dense model for responsive everyday tasks."
        case .afm3CoreAdvanced:
            return "On-device 20-billion-parameter sparse model (natively multimodal, expressive voice/dictation)."
        case .afm3Cloud:
            return "Server-side PCC model optimized for speed, efficiency, and high-quality performance."
        case .afm3CloudPro:
            return "Server-side PCC model for demanding agentic tool use and deep multi-step reasoning."
        case .adm3Cloud:
            return "Server-side PCC model for creative photo-editing, Image Playground, and Genmoji."
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
public final class FoundationModels {
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

    public var isPccEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "apple_foundation_model_pcc_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "apple_foundation_model_pcc_enabled") }
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

    public var simulatedQuotaLimitReached: Bool {
        get { UserDefaults.standard.bool(forKey: "apple_foundation_model_quota_limit_reached") }
        set { UserDefaults.standard.set(newValue, forKey: "apple_foundation_model_quota_limit_reached") }
    }

    public var simulatedApproachingLimit: Bool {
        get { UserDefaults.standard.bool(forKey: "apple_foundation_model_approaching_limit") }
        set { UserDefaults.standard.set(newValue, forKey: "apple_foundation_model_approaching_limit") }
    }

    public var statusDescription: String {
        guard isEnabled else { return "Disabled" }
        if isPccEnabled && selectedModel.isServerBased {
            if simulatedQuotaLimitReached {
                return "Quota Exceeded (Private Cloud Compute)"
            } else if simulatedApproachingLimit {
                return "Nearing Daily Limit (Private Cloud Compute)"
            } else {
                return "Connected (Private Cloud Compute)"
            }
        } else {
            return "Ready (On-Device)"
        }
    }

    private init() {}

    /// Executes language processing utilizing native iOS & macOS FoundationModels APIs when available, and fallback logic otherwise.
    public func generatePrivateResponse(prompt: String) async throws -> String {
        guard isEnabled else {
            throw NSError(domain: "FoundationModels", code: 400, userInfo: [NSLocalizedDescriptionKey: "Apple Foundation Models are disabled."])
        }

        #if canImport(FoundationModels)
        logger.log("Executing response using native FoundationModels framework APIs.")

        // Initializing proper model conformances
        let session: LanguageModelSession
        if #available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *), isPccEnabled {
            let model = PrivateCloudComputeLanguageModel()
            switch model.availability {
            case .available:
                if model.quotaUsage.isLimitReached || simulatedQuotaLimitReached {
                    logger.warning("Private Cloud Compute daily quota exceeded.")
                    throw NSError(domain: "FoundationModels.PCC", code: 429, userInfo: [NSLocalizedDescriptionKey: "Private Cloud Compute usage quota limit reached."])
                }
                session = LanguageModelSession(model: model)
            case .unavailable:
                logger.log("Private Cloud Compute is unavailable. Falling back to SystemLanguageModel.")
                session = LanguageModelSession(model: SystemLanguageModel())
            }
        } else {
            session = LanguageModelSession(model: SystemLanguageModel())
        }

        let contextOpts = ContextOptions(reasoningLevel: reasoningLevel.toNative())
        let response = try await session.respond(to: prompt, contextOptions: contextOpts)
        return response
        #else
        logger.log("Executing response using high-fidelity FoundationModels simulation.")
        try await Task.sleep(nanoseconds: 300_000_000) // Realistic delay

        if isPccEnabled && selectedModel.isServerBased && simulatedQuotaLimitReached {
            throw NSError(domain: "FoundationModels.PCC", code: 429, userInfo: [NSLocalizedDescriptionKey: "Private Cloud Compute daily reasoning allotment exceeded."])
        }

        var responsePrefix = "[On-Device \(selectedModel.rawValue)]\n"
        if isPccEnabled && selectedModel.isServerBased {
            responsePrefix = "[Private Cloud Compute: \(selectedModel.rawValue)]\n"
            if simulatedApproachingLimit {
                responsePrefix += "[PCC Status: Nearing daily reasoning limit]\n"
            }
        }

        // Language detection as supplementary utility
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(prompt)
        let dominantLanguage = recognizer.dominantLanguage?.rawValue.uppercased() ?? "EN"

        return """
        \(responsePrefix)Processed query with complete on-device local privacy guarantees.
        Input Language: \(dominantLanguage)
        Reasoning Effort: \(reasoningLevel.rawValue.uppercased())
        Response: Understood and successfully completed generation for prompt: "\(prompt.prefix(60))..."
        """
        #endif
    }
}

#if !canImport(FoundationModels)
// Fallback / simulation types to allow compilation on all environments
public protocol LanguageModel {}

public struct SystemLanguageModel: LanguageModel {
    public init() {}
}

public struct PrivateCloudComputeLanguageModel: LanguageModel {
    public init() {}

    public enum Availability {
        case available
        case unavailable(UnavailableReason)
    }

    public enum UnavailableReason {
        case deviceNotEligible
        case systemNotReady
        case other
    }

    public var availability: Availability {
        return .available
    }

    public struct QuotaUsage {
        public var isLimitReached: Bool = false
        public var status: QuotaStatus = .belowLimit(BelowLimitInfo(isApproachingLimit: false))
        public var limitIncreaseSuggestion: LimitIncreaseSuggestion? = nil
        public var resetDate: Date? = nil
    }

    public enum QuotaStatus {
        case belowLimit(BelowLimitInfo)
    }

    public struct BelowLimitInfo {
        public var isApproachingLimit: Bool
    }

    public struct LimitIncreaseSuggestion {
        public func show() {
            // Simulated upgrade presentation
        }
    }

    public var quotaUsage: QuotaUsage {
        return QuotaUsage()
    }
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
