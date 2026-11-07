import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct FoundationModelsProvider: AssistantProvider {
    public let kind = ProviderKind.foundationModels

    public static let modelID = "AFM 3 Core"
    public static let modelDisplayName = "Apple AFM 3 Core (On-Device)"

    public init() {}

    public static var unavailableHint: String {
        "Apple Foundation Models is not available on this device. It needs macOS 26 or later on an Apple Intelligence-capable Mac, with Apple Intelligence turned on."
    }

    public func availability() async -> ProviderAvailability {
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return await realAvailability()
        }
        return .notInstalled(hint: Self.unavailableHint)
#else
        return .notInstalled(hint: Self.unavailableHint)
#endif
    }

    public func contextWindow(model: String) async -> Int? {
        guard model == Self.modelID else { return nil }
#if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else { return nil }
            return await SystemLanguageModel.default.contextSize
        }
#endif
        return nil
    }

    public func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        eventStream { out in
            let prompt = Self.promptText(request)
            guard !prompt.isEmpty else { throw AssistantError.failed("There is no message to send.") }
#if canImport(FoundationModels)
            if #available(macOS 26.0, iOS 26.0, *) {
                try await Self.stream(request: request, prompt: prompt, out: out)
                return
            }
            throw AssistantError.failed(Self.unavailableHint)
#else
            throw AssistantError.failed(Self.unavailableHint)
#endif
        }
    }

    static func promptText(_ request: ChatRequest) -> String {
        var parts: [String] = []
        for message in request.messages.dropLast() {
            parts.append("<\(message.role.rawValue)>\n\(message.content)\n</\(message.role.rawValue)>")
        }
        if let last = request.messages.last {
            parts.append(last.content)
        }
        return parts.joined(separator: "\n\n")
    }

    static func delta(_ snapshot: String, after previous: String) -> String? {
        if snapshot == previous { return nil }
        if snapshot.hasPrefix(previous) {
            let d = String(snapshot.dropFirst(previous.count))
            return d.isEmpty ? nil : d
        }
        return snapshot
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private func realAvailability() async -> ProviderAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            let window = await SystemLanguageModel.default.contextSize
            return .ready([ModelInfo(id: Self.modelID, displayName: Self.modelDisplayName, contextWindow: window)])
        case .unavailable(let reason):
            if case .deviceNotEligible = reason {
                return .notInstalled(hint: "This device cannot run Apple Foundation Models. It needs an Apple Intelligence-capable Mac.")
            }
            return .failed(Self.unavailableMessage(for: reason))
        @unknown default:
            return .failed("Apple Foundation Models reported an unknown availability state.")
        }
    }

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

    @available(macOS 26.0, iOS 26.0, *)
    private static func stream(
        request: ChatRequest,
        prompt: String,
        out: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        guard SystemLanguageModel.default.isAvailable else {
            if case .unavailable(let reason) = SystemLanguageModel.default.availability {
                throw AssistantError.failed(Self.unavailableMessage(for: reason))
            }
            throw AssistantError.failed(Self.unavailableHint)
        }
        let instructions: Instructions? = request.instructions.isEmpty ? nil : Instructions(request.instructions)
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        var emitted = ""
        do {
            for try await snapshot in session.streamResponse(to: prompt) {
                try Task.checkCancellation()
                let text = snapshot.content
                if let d = Self.delta(text, after: emitted) {
                    out.yield(.text(d))
                }
                emitted = text
            }
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(error)
        }
        out.yield(.finished(nil))
    }

    @available(macOS 26.0, iOS 26.0, *)
    private static func mapGenerationError(_ error: LanguageModelSession.GenerationError) -> AssistantError {
        if case .exceededContextWindowSize = error {
            return .failed("The conversation is too long for the Apple Foundation Models on-device model. Start a new conversation or shorten the request.")
        }
        if case .rateLimited = error {
            return .temporarilyUnavailable("Apple Foundation Models is busy right now. Try again shortly.")
        }
        if case .guardrailViolation = error {
            return .failed("Apple Foundation Models declined this request.")
        }
        return .failed(error.localizedDescription)
    }
#endif
}
