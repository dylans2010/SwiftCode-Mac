// ChatController.swift
//
// Ported from Legacy SwiftCode/Features/AI/ChatController.swift (Dylan's
// own code; direct port authorised under MIT). Landed by H-E (H-E5's first
// pass left it internal, @Observable, and calling the nonexistent
// `LLMService.shared.sanitizeResponse` against the wrong `ChatMessage`
// initialiser — corrected here).
// Destination per Audit A: SwiftCodeAssistant/Core.swift's module —
// carried here as its own file (one type per file) instead.
//
// Adaptations (the Legacy file cannot land verbatim):
// - Legacy `ChatMessage` (Identifiable, id/timestamp, role: MessageRole)
//   is NOT ported: `Core.swift` already declares the canonical
//   `ChatMessage` (role: ChatRole, content) and a second declaration
//   would collide. The controller's `messages` are the destination
//   `ChatMessage`; roles map `.user` -> `.user`, `.assistant` ->
//   `.assistant` (ChatRole also has `.system`, unused here).
// - `MessageRole` IS ported (Audit A lists it missing) for Legacy
//   parity, but the controller itself uses `ChatRole`.
// - `LLMService` landed in production after this file was first written
//   (`SwiftCodeAssistant/LLMService.swift:110`, public, with
//   `sanitizeResponse(_:relativeTo:)` at :496 — byte-identical behaviour
//   to Legacy `LLMService.swift:496-529`), so the controller delegates to
//   `LLMService.shared.sanitizeResponse` instead of carrying a private copy.
// - Public + ObservableObject (not @Observable): `ChatAIInterfaceView`
//   (swiftcode-ide) uses `ChatController.shared` cross-module and
//   holds it in `@StateObject`, which requires ObservableObject.
// - `CodexModelRouter` and `LLMError` (both cases used here) already
//   exist in-target; no changes needed there.
//
// Known remainder (NOT this file): `ChatAIInterfaceView` iterates
// `controller.messages` with plain `ForEach` and reads `message.id`
// (:56-57, :68) — the destination `ChatMessage` has no `id`, so that
// view still needs its own missing-types work (`ChatMessageBubble`,
// `SlashCommandList`, `TypingIndicatorBubble`, etc. are also absent).
// Do not "fix" it by adding a stored `id` to Core.swift's ChatMessage:
// that would change its Equatable/Codable behaviour for every provider.

import Foundation

/// Legacy chat role (user/assistant). Retained for parity with Legacy
/// `ChatController.swift`; the controller itself uses `ChatRole`.
public enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
}

@MainActor
public final class ChatController: ObservableObject {
    public static let shared = ChatController()

    @Published public var messages: [ChatMessage] = []
    @Published public var isGenerating = false

    private let unavailableModelMessage = "No AI model available. Add an API key or download an offline model."

    public init() {}

    public func sendMessage(_ text: String, useContext: Bool) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        appendMessage(role: .user, content: prompt)
        await generateAssistantReply(for: prompt, useContext: useContext)
    }

    public func sendAgentMessage(_ text: String, useContext: Bool) async {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }

        appendMessage(role: .user, content: prompt)
        await generateAssistantReply(for: prompt, useContext: useContext)
    }

    private func generateAssistantReply(for prompt: String, useContext: Bool) async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let response = try await CodexModelRouter().routePrompt(prompt, useContext: useContext)
            let normalizedResponse = LLMService.shared.sanitizeResponse(response, relativeTo: prompt)

            if normalizedResponse.isEmpty {
                appendMessage(role: .assistant, content: "I couldn't generate a meaningful response. Please try rephrasing your request.")
            } else {
                appendMessage(role: .assistant, content: normalizedResponse)
            }
        } catch let error as LLMError {
            switch error {
            case .missingOfflineDefaultModel, .offlineFallbackUnavailable:
                appendMessage(role: .assistant, content: unavailableModelMessage)
            default:
                appendMessage(role: .assistant, content: "Request failed: \(error.localizedDescription)")
            }
        } catch {
            appendMessage(role: .assistant, content: "Request failed: \(error.localizedDescription)")
        }
    }

    private func appendMessage(role: ChatRole, content: String) {
        messages.append(ChatMessage(role, content))
    }
}
