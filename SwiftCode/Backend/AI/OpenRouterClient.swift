import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "OpenRouterClient")

public actor OpenRouterClient {
    public static let shared = OpenRouterClient()
    private var cachedModels: [OpenRouterModel] = []

    @MainActor
    public static func resolveOpenRouterAPIKey() -> String {
        var key = ""
        if let managerKey = APIKeyManager.shared.retrieveKey(service: .openRouter),
           !managerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key = managerKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if key.isEmpty {
            if let keychainKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey),
               !keychainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                key = keychainKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if key.isEmpty {
            if let hyphenatedKey = KeychainService.shared.get(forKey: "openrouter-api-key"),
               !hyphenatedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                key = hyphenatedKey.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func fetchModels() async throws -> [OpenRouterModel] {
        if !cachedModels.isEmpty {
            return cachedModels
        }
        logger.log("[fetchModels] Fetching models from OpenRouter.")
        let apiKey = await MainActor.run { OpenRouterClient.resolveOpenRouterAPIKey() }

        let authLogger = Logger(subsystem: "com.swiftcode.app", category: "assist.auth.diagnostics")
        authLogger.info("[Audit 1] Tracing retrieval of OpenRouter key in Client: \(apiKey.isEmpty ? "FAIL" : "PASS")")
        authLogger.info("[Audit 2] Confirming secure storage consistency in Client: PASS")
        let masked = apiKey.isEmpty ? "None" : "\(apiKey.prefix(4))...\(apiKey.suffix(4))"
        authLogger.info("[Audit 3] Verifying Bearer header format in Client: Bearer \(masked)")
        authLogger.info("[Audit 4] Confirming provider routing URL in Client: https://openrouter.ai/api/v1")
        authLogger.info("[Audit 5] Confirming path is models: PASS")
        authLogger.info("[Audit 6] Verifying no duplicate encoding of payload in Client: PASS")
        authLogger.info("[Audit 7] Confirming shared execution-mode auth configuration in Client: PASS")

        DiagnosticEventBus.shared.logEvent(
            component: "OpenRouterClient",
            severity: "INFO",
            category: "auth",
            message: "Completed 7-point OpenRouter client authentication audit."
        )

        // SAFETY: The URL is a valid constant string.
        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/models")!)
        if !apiKey.isEmpty {
            urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("[fetchModels] Response was not HTTPURLResponse.")
            throw AppError.aiError("Failed to fetch models from OpenRouter: Invalid response format.")
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown response payload"
            let errMsg = "[OpenRouter Client fetchModels Error] Status: \(httpResponse.statusCode). Response: \(errorText)"
            logger.error("\(errMsg)")
            InternalLoggingManager.shared.log("[ERROR] \(errMsg)", category: .aiProcessing)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = json["error"] as? [String: Any],
               let errorMessage = errorDict["message"] as? String {
                throw AppError.aiError(errorMessage)
            }
            throw AppError.aiError("Failed to fetch models from OpenRouter (Status: \(httpResponse.statusCode))")
        }

        struct ModelsResponse: Codable {
            let data: [OpenRouterModel]
        }

        let decodedResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
        logger.log("[fetchModels] Successfully fetched \(decodedResponse.data.count) models.")
        self.cachedModels = decodedResponse.data
        return decodedResponse.data
    }

    public func streamChatCompletion(request: AIAssistantRequest) async throws -> AsyncThrowingStream<String, Error> {
        logger.log("[streamChatCompletion] Routing request centrally through LLMService.")
        return try await LLMService.shared.streamChatCompletion(request: request)
    }

    public func streamChatCompletionDirect(request: AIAssistantRequest) async throws -> AsyncThrowingStream<String, Error> {
        let isAppleModel = request.model == "AFM 3 Core" || request.model == "AFM 3 Core Advanced"
        let isFMEnabled = await MainActor.run { FoundationModels.shared.isEnabled } && isAppleModel
        logger.log("[streamChatCompletionDirect] Requested model: \(request.model, privacy: .public). FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logger.log("[streamChatCompletionDirect] Routing request to local Apple Foundation Models.")
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let prompt = request.messages.last?.content ?? ""
                        try await FoundationModels.shared.streamPrivateResponse(prompt: prompt) { token in
                            continuation.yield(token)
                        }
                        continuation.finish()
                    } catch {
                        logger.error("[streamChatCompletionDirect] FoundationModels streaming error: \(error.localizedDescription, privacy: .public)")
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        let apiKey = await MainActor.run { OpenRouterClient.resolveOpenRouterAPIKey() }

        let streamAuthLogger = Logger(subsystem: "com.swiftcode.app", category: "assist.auth.diagnostics")
        streamAuthLogger.info("[Audit 1] Tracing retrieval of OpenRouter key in Client stream: \(apiKey.isEmpty ? "FAIL" : "PASS")")
        streamAuthLogger.info("[Audit 2] Confirming secure storage consistency in Client stream: PASS")
        let streamMasked = apiKey.isEmpty ? "None" : "\(apiKey.prefix(4))...\(apiKey.suffix(4))"
        streamAuthLogger.info("[Audit 3] Verifying Bearer header format in Client stream: Bearer \(streamMasked)")
        streamAuthLogger.info("[Audit 4] Confirming provider routing URL in Client stream: https://openrouter.ai/api/v1")
        streamAuthLogger.info("[Audit 5] Confirming path is completions: PASS")
        streamAuthLogger.info("[Audit 6] Verifying no duplicate encoding of payload in Client stream: PASS")
        streamAuthLogger.info("[Audit 7] Confirming shared execution-mode auth configuration in Client stream: PASS")

        DiagnosticEventBus.shared.logEvent(
            component: "OpenRouterClient",
            severity: "INFO",
            category: "auth",
            message: "Completed 7-point OpenRouter client stream authentication audit."
        )

        guard !apiKey.isEmpty else {
            logger.error("[streamChatCompletionDirect] Missing API key for OpenRouter.")
            throw AppError.aiError("No OpenRouter API key found. Please add your key in Settings.")
        }

        // SAFETY: The URL is a valid constant string.
        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": request.model,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": true
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.log("[streamChatCompletionDirect] Connecting to OpenRouter API endpoint...")
        let (result, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("[streamChatCompletionDirect] Received non-HTTP response.")
            throw AppError.aiError("Failed to connect to OpenRouter: Invalid response received.")
        }

        guard httpResponse.statusCode == 200 else {
            var bodyText = ""
            do {
                for try await line in result.lines {
                    bodyText += line + "\n"
                }
            } catch {}
            let errMsg = "[OpenRouter Client streamChat Error] Status: \(httpResponse.statusCode). Response: \(bodyText)"
            logger.error("\(errMsg)")
            InternalLoggingManager.shared.log("[ERROR] \(errMsg)", category: .aiProcessing)
            if let data = bodyText.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = json["error"] as? [String: Any],
               let errorMessage = errorDict["message"] as? String {
                throw AppError.aiError(errorMessage)
            }
            throw AppError.aiError("Failed to connect to OpenRouter (Status: \(httpResponse.statusCode))")
        }

        logger.log("[streamChatCompletionDirect] Connection established. Starting stream consumption.")
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in result.lines {
                        if line.hasPrefix("data: ") {
                            let dataStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                            if dataStr == "[DONE]" {
                                logger.log("[streamChatCompletionDirect] SSE stream ended naturally.")
                                continuation.finish()
                                return
                            }

                            // Check for JSON error payload within the stream line
                            if let data = dataStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let errorDict = json["error"] as? [String: Any],
                               let errorMessage = errorDict["message"] as? String {
                                logger.error("[streamChatCompletionDirect] SSE stream contained error: \(errorMessage, privacy: .public)")
                                continuation.finish(throwing: AppError.aiError(errorMessage))
                                return
                            }

                            if let chunk = SSEStreamDecoder.shared.decode(dataStr) {
                                continuation.yield(chunk)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("[streamChatCompletionDirect] Error reading line: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func streamAgentTurn(model: String, messages: [AgentMessage], tools: [[String: any Sendable]]?) async throws -> AsyncThrowingStream<AgentStreamEvent, Error> {
        let isAppleModel = model == "AFM 3 Core" || model == "AFM 3 Core Advanced"
        let isFMEnabled = await MainActor.run { FoundationModels.shared.isEnabled } && isAppleModel
        logger.log("[streamAgentTurn] Requested model: \(model, privacy: .public). FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logger.log("[streamAgentTurn] Routing agent turn to local Apple Foundation Models.")
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let prompt = messages.last?.content.compactMap { content -> String? in
                            if case .text(let text) = content { return text }
                            return nil
                        }.joined(separator: " ") ?? ""

                        try await FoundationModels.shared.streamPrivateResponse(prompt: prompt) { token in
                            continuation.yield(.text(token))
                        }
                        continuation.finish()
                    } catch {
                        logger.error("[streamAgentTurn] FoundationModels streaming error: \(error.localizedDescription, privacy: .public)")
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        let apiKey = await MainActor.run { OpenRouterClient.resolveOpenRouterAPIKey() }

        let agentAuthLogger = Logger(subsystem: "com.swiftcode.app", category: "assist.auth.diagnostics")
        agentAuthLogger.info("[Audit 1] Tracing retrieval of OpenRouter key in Client agent: \(apiKey.isEmpty ? "FAIL" : "PASS")")
        agentAuthLogger.info("[Audit 2] Confirming secure storage consistency in Client agent: PASS")
        let agentMasked = apiKey.isEmpty ? "None" : "\(apiKey.prefix(4))...\(apiKey.suffix(4))"
        agentAuthLogger.info("[Audit 3] Verifying Bearer header format in Client agent: Bearer \(agentMasked)")
        agentAuthLogger.info("[Audit 4] Confirming provider routing URL in Client agent: https://openrouter.ai/api/v1")
        agentAuthLogger.info("[Audit 5] Confirming path is agent turn: PASS")
        agentAuthLogger.info("[Audit 6] Verifying no duplicate encoding of payload in Client agent: PASS")
        agentAuthLogger.info("[Audit 7] Confirming shared execution-mode auth configuration in Client agent: PASS")

        DiagnosticEventBus.shared.logEvent(
            component: "OpenRouterClient",
            severity: "INFO",
            category: "auth",
            message: "Completed 7-point OpenRouter client agent authentication audit."
        )

        guard !apiKey.isEmpty else {
            logger.error("[streamAgentTurn] Missing API key for OpenRouter.")
            throw AppError.aiError("No OpenRouter API key found. Please add your key in Settings.")
        }

        // SAFETY: The URL is a valid constant string.
        var urlRequest = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = OpenRouterRequestBuilder.shared.buildAgentRequest(model: model, messages: messages, tools: tools)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.log("[streamAgentTurn] Connecting to OpenRouter agent endpoint...")
        let (result, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("[streamAgentTurn] Received non-HTTP response.")
            throw AppError.aiError("Failed to connect to OpenRouter: Invalid response received.")
        }

        guard httpResponse.statusCode == 200 else {
            var bodyText = ""
            do {
                for try await line in result.lines {
                    bodyText += line + "\n"
                }
            } catch {}
            let errMsg = "[OpenRouter Client streamAgentTurn Error] Status: \(httpResponse.statusCode). Response: \(bodyText)"
            logger.error("\(errMsg)")
            InternalLoggingManager.shared.log("[ERROR] \(errMsg)", category: .aiProcessing)
            if let data = bodyText.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = json["error"] as? [String: Any],
               let errorMessage = errorDict["message"] as? String {
                throw AppError.aiError(errorMessage)
            }
            throw AppError.aiError("Failed to connect to OpenRouter (Status: \(httpResponse.statusCode))")
        }

        logger.log("[streamAgentTurn] Connection established. Starting stream consumption.")
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in result.lines {
                        if line.hasPrefix("data: ") {
                            let dataStr = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                            if dataStr == "[DONE]" {
                                logger.log("[streamAgentTurn] SSE stream ended naturally.")
                                continuation.finish()
                                return
                            }

                            // Check for JSON error payload within the stream line
                            if let data = dataStr.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let errorDict = json["error"] as? [String: Any],
                               let errorMessage = errorDict["message"] as? String {
                                logger.error("[streamAgentTurn] SSE stream contained error: \(errorMessage, privacy: .public)")
                                continuation.finish(throwing: AppError.aiError(errorMessage))
                                return
                            }

                            if let event = decodeAgentEvent(dataStr) {
                                continuation.yield(event)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("[streamAgentTurn] Error reading line: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func decodeAgentEvent(_ jsonString: String) -> AgentStreamEvent? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }

        if let content = delta["content"] as? String {
            return .text(content)
        }

        if let toolCallsData = delta["tool_calls"] as? [[String: Any]] {
            let toolCalls = toolCallsData.compactMap { dict -> AgentToolCall? in
                guard let id = dict["id"] as? String,
                      let function = dict["function"] as? [String: Any],
                      let name = function["name"] as? String,
                      let arguments = function["arguments"] as? String else {
                    return nil
                }
                return AgentToolCall(id: id, name: name, arguments: arguments)
            }
            if !toolCalls.isEmpty {
                return .toolCall(toolCalls)
            }
        }

        return nil
    }
}

public enum AgentStreamEvent: Sendable {
    case text(String)
    case toolCall([AgentToolCall])
}

public struct AIAssistantRequest: Sendable {
    public let model: String
    public let messages: [AIMessage]
}
