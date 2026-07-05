import Foundation

struct CodexResponseParser {
    func parseResponse(data: Data, response: URLResponse) throws -> LLMResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Invalid server response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodexErrorHandler.parseHTTPError(data: data, statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(CodexResponseEnvelope.self, from: data)
        let text = decoded.outputText ?? decoded.output.compactMap(\.flattenedText).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return LLMResponse(
            modelName: decoded.model,
            completionText: text,
            tokenUsage: decoded.usage.map {
                .init(promptTokens: $0.inputTokens, completionTokens: $0.outputTokens, totalTokens: $0.totalTokens)
            },
            latency: 0
        )
    }

    func parseStreamChunk(_ line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONDecoder().decode(CodexStreamEvent.self, from: data) else {
            return nil
        }
        return event.deltaText
    }
}
