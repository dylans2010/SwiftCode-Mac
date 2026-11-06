import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device Foundation Models back end (Apple Foundation Models
/// only: the single system model behind Apple Intelligence).
///
/// On-device, no network, no account, no sign-in, and no credential of any
/// kind: there is no endpoint to call, no key to store, and no provider
/// picker inside this provider — Apple's framework hands the session
/// whichever on-device model the OS installed. Legacy surfaced Foundation
/// Models in Assist only through model discovery
/// (`AssistModelDiscoveryService.generateAppleFoundationModels()`); it had
/// no separate Assist provider client, and its `selectedModel` was never
/// passed to the framework — `generatePrivateResponse` always built a
/// `LanguageModelSession` from `SystemLanguageModel()` whatever the
/// selection said. This provider therefore reports exactly one model: the
/// Legacy default entry (`AFM 3 Core`, display name
/// `Apple AFM 3 Core (On-Device)`). Legacy's second entry
/// (`AFM 3 Core Advanced`, 32,000 tokens) is deliberately not exposed:
/// there is no framework API to select it, and reporting it would be a
/// choice the user cannot make.
///
/// Everything that touches the framework lives behind
/// `#if canImport(FoundationModels)` plus a `#available(macOS 26.0,
/// iOS 26.0, *)` gate (the framework ships with macOS 26 / iOS 26).
/// Where the framework is absent the provider reports honestly
/// unavailable (`.notInstalled` with a hint naming the requirement) and
/// `send(_:)` fails instead of answering from canned text. Legacy's
/// `#else` simulation branch — canned titles, prompt-enhancement JSON,
/// and `[On-Device …] Processed query …` replies — is NOT ported.
///
/// The coordinator adds the `ProviderKind.foundationModels` case and the
/// `provider()` wiring at merge time; this file assumes that case exists
/// with exactly that name.
public struct FoundationModelsProvider: AssistantProvider {
    public let kind = ProviderKind.foundationModels

    /// The single on-device model, mirroring Legacy's default
    /// `AppleFoundationModel.afm3Core` entry. This is one model, not a
    /// list: Apple ships one system model and there is no `/models`
    /// endpoint to discover more.
    public static let modelID = "AFM 3 Core"
    public static let modelDisplayName = "Apple AFM 3 Core (On-Device)"

    public init() {}

    /// The hint shown where the framework cannot be used at all.
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

    /// The prompt sent to the session: earlier turns as tagged blocks,
    /// then the new message. The instructions travel separately as the
    /// session's `Instructions`, so they are not repeated here.
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

    /// The new text in a cumulative streaming snapshot, or `nil` when the
    /// snapshot adds nothing. `streamResponse` yields snapshots that each
    /// hold the whole reply so far, not deltas, so `ChatEvent`s carry only
    /// the suffix after what was already emitted. A snapshot that is not
    /// a prefix of the previous text (the model revised earlier text)
    /// is returned whole rather than silently dropped.
    static func delta(_ snapshot: String, after previous: String) -> String? {
        if snapshot == previous { return nil }
        if snapshot.hasPrefix(previous) {
            let d = String(snapshot.dropFirst(previous.count))
            return d.isEmpty ? nil : d
        }
        return snapshot
    }

#if canImport(FoundationModels)
    /// Availability from the system model itself. The context window is
    /// read live from `SystemLanguageModel.default.contextSize` — Legacy
    /// hardcoded 8,192 for this entry, but the installed model reports
    /// its own budget and that is what the host should budget against.
    @available(macOS 26.0, iOS 26.0, *)
    private func realAvailability() async -> ProviderAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            let window = await SystemLanguageModel.default.contextSize
            return .ready([ModelInfo(id: Self.modelID, displayName: Self.modelDisplayName, contextWindow: window)])
        case .unavailable(let reason):
            // The device can never run the model: report it as not
            // installed. Every other reason is a state that can change
            // (Apple Intelligence off, model still downloading), so it
            // is a failure with the action in the message.
            if case .deviceNotEligible = reason {
                return .notInstalled(hint: "This device cannot run Apple Foundation Models. It needs an Apple Intelligence-capable Mac.")
            }
            return .failed(Self.unavailableMessage(for: reason))
        @unknown default:
            return .failed("Apple Foundation Models reported an unknown availability state.")
        }
    }

    /// The user-facing reason the system model is unavailable. The
    /// reason cases are matched one by one (rather than a `switch`) so
    /// an unfamiliar reason still yields an honest message instead of a
    /// compile break on a future OS.
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

    /// One session per request (the session holds a transcript, so a
    /// fresh session keeps requests independent — the pattern Legacy
    /// used, one `LanguageModelSession` per `generatePrivateResponse`
    /// call). No tools are attached: Legacy never gave Foundation
    /// Models tools, and this provider does not add tool calling.
    /// Generation options (`maxOutputTokens`, sampling) are not mapped
    /// onto the framework's `GenerationOptions` in this slice — the
    /// exact `streamResponse(to:options:)` shape is unverified here, so
    /// the model runs on its defaults rather than on a guessed call.
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

    /// Framework generation failures as `AssistantError`s. Matched one
    /// by one (rather than a `switch`) so an unfamiliar error case still
    /// surfaces honestly instead of breaking the build on a future OS.
    /// The framework reports no token usage for a stream, so the
    /// finished event carries none.
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
