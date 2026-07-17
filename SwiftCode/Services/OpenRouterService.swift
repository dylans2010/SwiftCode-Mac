import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "OpenRouterService")

// MARK: - OpenRouter API Service

final class OpenRouterService: Sendable {
    static let shared = OpenRouterService()
    private init() {}

    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!

    // MARK: - Chat Completion (non-streaming)

    func chat(
        messages: [AIMessage],
        model: String,
        systemPrompt: String
    ) async throws -> String {
        logger.log("[chat] Centralizing request through LLMService.")
        return try await LLMService.shared.generateResponse(
            prompt: messages.last?.content ?? "",
            useContext: true,
            modelOverride: model,
            providerOverride: .openRouter
        )
    }

    func chatDirect(
        messages: [AIMessage],
        model: String,
        systemPrompt: String
    ) async throws -> String {
        let isFMEnabled = await MainActor.run { FoundationModels.shared.isEnabled }
        logger.log("[chatDirect] Requested model: \(model, privacy: .public). FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logger.log("[chatDirect] Routing request to local Apple Foundation Models.")
            let lastPrompt = messages.last?.content ?? ""
            return try await FoundationModels.shared.generatePrivateResponse(prompt: lastPrompt)
        }

        guard let apiKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey),
              !apiKey.isEmpty else {
            logger.error("[chatDirect] Missing API key for OpenRouter.")
            throw OpenRouterError.missingAPIKey
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SwiftCode iOS App", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/swiftcode/app", forHTTPHeaderField: "HTTP-Referer")

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlError as URLError {
            throw OpenRouterError.networkError(code: urlError.code.rawValue, description: urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse(detail: "Response was not an HTTP response.")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterError.apiError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        do {
            let decoded = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw OpenRouterError.emptyResponse
            }
            return content
        } catch is OpenRouterError {
            throw OpenRouterError.emptyResponse
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw OpenRouterError.decodingError(detail: error.localizedDescription, rawBody: raw)
        }
    }

    // MARK: - Streaming Chat Completion

    func streamChat(
        messages: [AIMessage],
        model: String,
        systemPrompt: String,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        logger.log("[streamChat] Centralizing streaming request through LLMService.")
        try await LLMService.shared.streamChat(
            messages: messages,
            model: model,
            systemPrompt: systemPrompt,
            onToken: onToken
        )
    }

    func streamChatDirect(
        messages: [AIMessage],
        model: String,
        systemPrompt: String,
        onToken: @escaping @Sendable (String) async -> Void
    ) async throws {
        let isFMEnabled = await MainActor.run { FoundationModels.shared.isEnabled }
        logger.log("[streamChatDirect] Requested model: \(model, privacy: .public). FoundationModels enabled: \(isFMEnabled).")

        if isFMEnabled {
            logger.log("[streamChatDirect] Routing request to local Apple Foundation Models.")
            let lastPrompt = messages.last?.content ?? ""
            try await FoundationModels.shared.streamPrivateResponse(prompt: lastPrompt) { token in
                await onToken(token)
            }
            return
        }

        guard let apiKey = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey),
              !apiKey.isEmpty else {
            logger.error("[streamChatDirect] Missing API key for OpenRouter.")
            throw OpenRouterError.missingAPIKey
        }

        let url = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SwiftCode iOS App", forHTTPHeaderField: "X-Title")
        request.setValue("https://github.com/swiftcode/app", forHTTPHeaderField: "HTTP-Referer")

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        apiMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": 0.7,
            "max_tokens": 4096,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let stream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (stream, response) = try await URLSession.shared.bytes(for: request)
        } catch let urlError as URLError {
            throw OpenRouterError.networkError(code: urlError.code.rawValue, description: urlError.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse(detail: "Response was not an HTTP response.")
        }

        guard httpResponse.statusCode == 200 else {
            // Collect the body for better error reporting
            var bodyData = Data()
            for try await byte in stream {
                bodyData.append(byte)
                if bodyData.count > 4096 { break }
            }
            let errorBody = String(data: bodyData, encoding: .utf8) ?? "Unknown error"
            throw OpenRouterError.apiError(statusCode: httpResponse.statusCode, body: errorBody)
        }

        for try await line in stream.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard jsonString != "[DONE]" else { break }

            guard let data = jsonString.data(using: .utf8) else { continue }

            // Check for JSON error payload within the stream line
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDict = json["error"] as? [String: Any],
               let errorMessage = errorDict["message"] as? String {
                logger.error("[streamChat] SSE stream contained error: \(errorMessage, privacy: .public)")
                throw OpenRouterError.apiError(statusCode: 400, body: errorMessage)
            }

            guard let chunk = try? JSONDecoder().decode(OpenRouterStreamChunk.self, from: data),
                  let token = chunk.choices.first?.delta.content else { continue }

            await onToken(token)
        }
    }

    // MARK: - Fetch Available Models

    func fetchModels() async throws -> [OpenRouterModel] {
        return try await OpenRouterClient.shared.fetchModels()
    }
}

// MARK: - Response Models

private struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct OpenRouterStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

private struct OpenRouterModelsResponse: Decodable {
    struct ModelData: Decodable {
        let id: String
        let name: String?
        let description: String?
    }
    let data: [ModelData]
}

// MARK: - Errors

enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case invalidResponse(detail: String)
    case emptyResponse
    case apiError(statusCode: Int, body: String)
    case networkError(code: Int, description: String)
    case decodingError(detail: String, rawBody: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "[OR-001] No OpenRouter API key found. Please add your key in Settings."
        case .invalidResponse(let detail):
            return "[OR-002] Invalid response from the API: \(detail)"
        case .emptyResponse:
            return "[OR-003] The AI returned an empty response."
        case let .apiError(code, body):
            let hint: String
            switch code {
            case 401: hint = "Invalid API key. Check your OpenRouter key in Settings."
            case 402: hint = "Insufficient credits on your OpenRouter account."
            case 403: hint = "Access denied. The selected model may require a paid plan."
            case 404: hint = "Model not found. The selected model ID may be invalid."
            case 429: hint = "Rate limited. Please wait a moment and try again."
            case 500...599: hint = "OpenRouter server error. Try again later."
            default: hint = body
            }
            return "[OR-\(code)] API error \(code): \(hint)"
        case let .networkError(code, description):
            return "[OR-NET-\(code)] Network error: \(description)"
        case let .decodingError(detail, _):
            return "[OR-004] Failed to decode API response: \(detail)"
        }
    }
}
