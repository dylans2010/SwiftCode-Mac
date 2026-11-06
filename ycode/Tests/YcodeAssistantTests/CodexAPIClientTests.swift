import Foundation
import Testing
@testable import YcodeAssistant

// The Codex API-key client (ported from Legacy's Backend/Codex) against a
// stub transport. No live network, no real key anywhere — the "keys" here
// are placeholders like "user-key".

/// A URLProtocol stub: the handler answers every request from canned
/// data. No live network.
final class CodexStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, headers: [String: String], body: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CodexStubURLProtocol.self]
    return URLSession(configuration: config)
}

private func envelopeJSON(text: String, inputTokens: Int = 10, outputTokens: Int = 5) -> Data {
    let json: [String: Any] = [
        "model": "gpt-5-codex",
        "output": [["content": [["text": text]]]],
        "usage": ["input_tokens": inputTokens, "output_tokens": outputTokens, "total_tokens": inputTokens + outputTokens]
    ]
    return try! JSONSerialization.data(withJSONObject: json)
}

@Suite(.serialized)
@MainActor
struct CodexAPIClientTests {
    @Test func requestBuilderTargetsResponsesEndpoint() throws {
        let builder = CodexRequestBuilder()
        let request = try builder.makeRequest(model: "gpt-5-codex", prompt: "hi", session: CodexSession(messages: []), taskType: .general, stream: false)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5-codex")
        #expect(json["stream"] as? Bool == false)
        #expect(json["store"] as? Bool == false)
    }

    @Test func requestBuilderIncludesLastTenMessages() throws {
        let builder = CodexRequestBuilder()
        var messages: [CodexMessage] = []
        for i in 0..<12 { messages.append(.user("message \(i)")) }
        let session = CodexSession(messages: messages)
        let request = try builder.makeRequest(model: "gpt-5-codex", prompt: "latest", session: session, taskType: .debugging, stream: false)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try #require(json["input"] as? [[String: Any]])
        // system + last 10 messages + new prompt = 12 items
        #expect(input.count == 12)
        let texts = input.compactMap { ($0["content"] as? [[String: Any]])?.first?["text"] as? String }
        #expect(texts.contains("message 2"))
        #expect(!texts.contains("message 0"))
        #expect(!texts.contains("message 1"))
        #expect(texts.last == "latest")
    }

    @Test func parserReadsEnvelopeTextAndUsage() throws {
        let parser = CodexResponseParser()
        let url = URL(string: "https://api.openai.com/v1/responses")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let parsed = try parser.parseResponse(data: envelopeJSON(text: "hello"), response: response)
        #expect(parsed.modelName == "gpt-5-codex")
        #expect(parsed.completionText == "hello")
        #expect(parsed.tokenUsage?.promptTokens == 10)
        #expect(parsed.tokenUsage?.completionTokens == 5)
        #expect(parsed.tokenUsage?.totalTokens == 15)
    }

    @Test func parserMaps401ToInvalidKeyAnd429ToRateLimited() {
        let parser = CodexResponseParser()
        let url = URL(string: "https://api.openai.com/v1/responses")!
        for (status, expected) in [(401, CodexAPIError.invalidKey), (429, CodexAPIError.rateLimited)] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            #expect(throws: expected) {
                try parser.parseResponse(data: Data(), response: response)
            }
        }
    }

    @Test func parserReadsStreamDelta() {
        let parser = CodexResponseParser()
        #expect(parser.parseStreamChunk(#"{"type":"response.output_text.delta","delta":"hi"}"#) == "hi")
        #expect(parser.parseStreamChunk("not json") == nil)
    }

    @Test func errorHandlerMessagesAreUserFacing() {
        #expect(CodexErrorHandler.userFacingMessage(for: CodexAPIError.invalidKey).contains("invalid or expired"))
        #expect(CodexErrorHandler.userFacingMessage(for: CodexAPIError.rateLimited).contains("reached its limit"))
        #expect(CodexErrorHandler.userFacingMessage(for: CodexAPIError.unknown("boom")) == "boom")
    }

    @Test func serviceSendsBearerKeyAndReturnsText() async throws {
        var seenRequest: URLRequest?
        CodexStubURLProtocol.handler = { request in
            seenRequest = request
            return (200, ["Content-Type": "application/json"], envelopeJSON(text: "done"))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let service = CodexService(session: stubSession())
        let result = try await service.send(prompt: "write code", session: CodexSession(messages: []), apiKey: "user-key", model: "gpt-5-codex", taskType: .codeGeneration)
        #expect(result.completionText == "done")
        #expect(seenRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer user-key")
    }

    @Test func serviceValidateAPIKeyReturnsFalseOn401() async {
        CodexStubURLProtocol.handler = { _ in
            (401, ["Content-Type": "application/json"], Data(#"{"error":{"message":"bad key"}}"#.utf8))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let service = CodexService(session: stubSession())
        #expect(await service.validateAPIKey("bad-key", model: "gpt-5-codex") == false)
    }

    @Test func managerUsesUserKeyFirstAndRecordsSession() async throws {
        CodexStubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], envelopeJSON(text: "here is code"))
        }
        defer { CodexStubURLProtocol.handler = nil }
        let store = MemorySecretStore()
        try store.write(Data("user-key".utf8), for: CodexManager.userKeyAccount)
        try store.write(Data("app-key".utf8), for: CodexManager.appKeyAccount)
        let manager = CodexManager(service: CodexService(session: stubSession()), tracker: CodexUsageTracker(), store: store)
        #expect(manager.usageMode == .unlimitedUserControlled)
        #expect(manager.activeAPIKey == "user-key")
        let text = try await manager.sendPrompt("generate a function")
        #expect(text == "here is code")
        #expect(manager.activeSession.messages.count == 2)
        #expect(manager.activeSession.messages.first?.role == "user")
        #expect(manager.activeSession.lastResponse == "here is code")
    }

    @Test func managerThrowsInvalidKeyWithNoKeyConfigured() async {
        let manager = CodexManager(service: CodexService(session: stubSession()), tracker: CodexUsageTracker(), store: MemorySecretStore())
        #expect(manager.hasValidConfiguration == false)
        await #expect(throws: CodexAPIError.invalidKey) {
            try await manager.sendPrompt("hello")
        }
    }

    @Test func managerEnforcesAppOwnedRequestLimit() async {
        let store = MemorySecretStore()
        try? store.write(Data("app-key".utf8), for: CodexManager.appKeyAccount)
        let tracker = CodexUsageTracker()
        for _ in 0..<200 {
            tracker.record(prompt: "x", response: "y", tokenUsage: nil, mode: .restrictedAppControlled)
        }
        let manager = CodexManager(service: CodexService(session: stubSession()), tracker: tracker, store: store)
        #expect(manager.usageMode == .restrictedAppControlled)
        await #expect(throws: CodexAPIError.rateLimited) {
            try await manager.sendPrompt("one more")
        }
    }

    @Test func usageTrackerCapsRestrictedTotalsAt200k() {
        let tracker = CodexUsageTracker()
        tracker.record(prompt: String(repeating: "x", count: 1_000_000), response: String(repeating: "y", count: 1_000_000), tokenUsage: nil, mode: .restrictedAppControlled)
        #expect(tracker.estimatedPromptTokens == 200_000)
        #expect(tracker.estimatedCompletionTokens == 200_000)
        #expect(tracker.requestCount == 1)
    }

    @Test func usageTrackerUsesRealUsageWhenProvided() {
        let tracker = CodexUsageTracker()
        tracker.record(prompt: "short", response: "short", tokenUsage: .init(promptTokens: 42, completionTokens: 7, totalTokens: 49), mode: .unlimitedUserControlled)
        #expect(tracker.estimatedPromptTokens == 42)
        #expect(tracker.estimatedCompletionTokens == 7)
        #expect(tracker.estimatedTotalTokens == 49)
    }
}
