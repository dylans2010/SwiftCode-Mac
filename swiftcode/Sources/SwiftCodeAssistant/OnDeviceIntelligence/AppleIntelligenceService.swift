// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/On Device Intelligence/AppleIntelligenceService.swift
//   (Legacy commit d51a8f0d)
//
// Adaptation — this is the important one. Legacy's `process` did NOT
// call Apple Intelligence at all: `summarize` returned the first three
// sentences, `rewrite` bulleted the lines, `codeAssist` returned a
// fixed plan template, and `generate` echoed the prompt back with a
// language tag from `NLLanguageRecognizer`. Those are canned text
// transforms presented as on-device inference, so they are NOT ported
// as behaviour. The real on-device inference path in this target is
// `FoundationModelsProvider` (Apple Foundation Models, model
// "AFM 3 Core"), so `process` now routes each task through it: the
// task becomes the session instructions, the session history plus the
// new prompt becomes the request, and the streamed reply is collected.
// The task routing, the `TaskType` cases, and the `process(prompt:task:
// session:)` shape are Legacy's own; only the inference itself changed,
// from fake to the destination's real provider. Where Foundation
// Models is absent, `send` throws its honest unavailable error
// instead of answering from canned text — exactly as
// FoundationModelsProvider documents.

import Foundation

public final class AppleIntelligenceService: Sendable {
    public enum TaskType: String, Sendable, Codable, CaseIterable {
        case textGeneration
        case summarization
        case rewriting
        case codeAssist
    }

    private let provider = FoundationModelsProvider()

    public init() {}

    public func process(prompt: String, task: TaskType, session: OnDeviceSession) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var messages: [ChatMessage] = session.history.map { message in
            switch message.role {
            case .user: ChatMessage(.user, message.content)
            case .assistant: ChatMessage(.assistant, message.content)
            case .system: ChatMessage(.system, message.content)
            }
        }
        messages.append(ChatMessage(.user, trimmed))
        let request = ChatRequest(
            model: FoundationModelsProvider.modelID,
            instructions: Self.instructions(for: task),
            messages: messages
        )
        var response = ""
        for try await event in provider.send(request) {
            if case let .text(text) = event {
                response += text
            }
        }
        return response
    }

    /// The task as instructions to the on-device model. Legacy expressed
    /// each task as a fixed text transform; here the task is a real
    /// instruction and the model does the work.
    private static func instructions(for task: TaskType) -> String {
        switch task {
        case .textGeneration:
            return ""
        case .summarization:
            return "Summarize the following text concisely, keeping only the key points."
        case .rewriting:
            return "Rewrite the following text more clearly, preserving its meaning."
        case .codeAssist:
            return "You are a coding assistant. Inspect the relevant files and dependencies the user describes, propose the requested code changes, and say how to validate them with targeted build or test commands."
        }
    }
}
