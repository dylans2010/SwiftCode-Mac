import Foundation
import YcodeAssistant

public struct SDKAssistProviderResolution: Sendable {
    public let provider: any AssistantProvider
    public let modelID: String?

    public init(provider: any AssistantProvider, modelID: String?) {
        self.provider = provider
        self.modelID = modelID
    }
}

public protocol SDKAssistProviderResolving: Sendable {
    func resolveProvider(for session: SDKAssistSession) async throws -> SDKAssistProviderResolution
}

public actor SDKAssistHostBackend: SDKAssistBackend {
    public static let shared = SDKAssistHostBackend()

    public static let textCompletionProviderKinds: Set<ProviderKind> = [
        .ollama, .llamaCpp, .openAI, .openRouter, .foundationModels, .scCloud,
    ]

    public static let agentProviderKinds: Set<ProviderKind> = [
        .claudeCode, .codex, .antigravity, .acpAgent, .hermes, .openCode, .metaAssist,
    ]

    public static let defaultInstructions =
        "Answer the user's message directly. You are replying on behalf of an IDE extension; you have no tools and no access to the user's files or conversation."

    private var resolver: (any SDKAssistProviderResolving)?
    private var toolRunner: (any SDKAssistToolRunning)?

    public init(resolver: (any SDKAssistProviderResolving)? = nil) {
        self.resolver = resolver
    }

    public func install(resolver: any SDKAssistProviderResolving) {
        self.resolver = resolver
    }

    public func install(toolRunner: any SDKAssistToolRunning) {
        self.toolRunner = toolRunner
    }

    public func complete(session: SDKAssistSession, message: String) async throws -> String {
        guard !session.isClosed else {
            throw SDKError(code: .invalidArgument, message: "The Assist session is closed.")
        }
        let (provider, modelID) = try await resolveTextProvider(for: session)
        let request = Self.request(for: session, message: message, modelID: modelID)
        var text = ""
        do {
            for try await event in provider.send(request) {
                if case .text(let delta) = event { text += delta }
                if case .finished = event { break }
            }
        } catch {
            throw await Self.mapProviderError(error, providerKind: provider.kind, session: session)
        }
        return text
    }

    public func stream(session: SDKAssistSession, message: String) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !session.isClosed else {
                        throw SDKError(code: .invalidArgument, message: "The Assist session is closed.")
                    }
                    let (provider, modelID) = try await self.resolveTextProvider(for: session)
                    let request = Self.request(for: session, message: message, modelID: modelID)
                    do {
                        for try await event in provider.send(request) {
                            if case .text(let delta) = event { continuation.yield(delta) }
                            if case .finished = event { break }
                        }
                    } catch {
                        throw await Self.mapProviderError(error, providerKind: provider.kind, session: session)
                    }
                    continuation.yield("")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func executeTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult {
        guard !session.isClosed else {
            throw SDKError(code: .invalidArgument, message: "The Assist session is closed.")
        }
        guard let runner = toolRunner else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "Tool execution for extensions is not attached: no tool runner reachable from the SDK host enforces the extension's granted capabilities."
            )
        }
        guard session.allowedToolIDs.contains(call.toolName) else {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        if let live = await runner.liveAllowedToolIDs(for: session.extensionID),
           !live.contains(call.toolName) {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        do {
            return try await runner.runTool(session: session, call: call)
        } catch let error as SDKError {
            throw error
        } catch {
            let failure = SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "The host tool runner could not run the tool."
            )
            await SDKDeveloperLogger.shared.log(
                error: failure,
                diagnostics: [
                    "tool": call.toolName,
                    "session": session.id.uuidString,
                    "underlying": String(describing: type(of: error)),
                ],
                context: ["extension": session.extensionID]
            )
            throw failure
        }
    }

    private func resolveTextProvider(for session: SDKAssistSession) async throws -> (provider: any AssistantProvider, modelID: String?) {
        guard let resolver else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "No Assist provider resolver is installed. The host has not attached its Assist backend yet."
            )
        }
        let resolution = try await resolver.resolveProvider(for: session)
        guard Self.textCompletionProviderKinds.contains(resolution.provider.kind) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "The configured provider (\(resolution.provider.kind.displayName)) runs an agent on the user's machine and cannot serve extension turns. Choose a text-completion provider in Settings."
            )
        }
        let availability = await resolution.provider.availability()
        guard availability.isReady else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: availability.hint ?? "The configured provider is not ready."
            )
        }
        return (resolution.provider, resolution.modelID)
    }

    private static func request(for session: SDKAssistSession, message: String, modelID: String?) -> ChatRequest {
        var messages = session.messages.map { ChatMessage($0.role == .assistant ? .assistant : .user, $0.content) }
        messages.append(ChatMessage(.user, message))
        return ChatRequest(
            model: modelID,
            instructions: session.systemPrompt ?? defaultInstructions,
            messages: messages,
            workingDirectory: nil,
            generation: .assistantDefault
        )
    }

    private static func mapProviderError(_ error: Error, providerKind: ProviderKind, session: SDKAssistSession) async -> SDKError {
        if let sdkError = error as? SDKError { return sdkError }
        let failure = SDKError(
            code: .serviceUnavailable,
            message: "Assist is not available for extensions right now.",
            suggestion: "The host provider (\(providerKind.displayName)) could not complete the request."
        )
        await SDKDeveloperLogger.shared.log(
            error: failure,
            diagnostics: [
                "provider": providerKind.rawValue,
                "session": session.id.uuidString,
                "underlying": String(describing: type(of: error)),
            ],
            context: ["extension": session.extensionID]
        )
        return failure
    }
}
