import Foundation
import Testing
@testable import YcodeAssistant

/// OpenRouter provider tests. The `/models` fixtures below are recorded
/// samples of the response shape (a `data` array of entries with `id`,
/// `name`, `context_length` and `supported_parameters`); every model id
/// uses the obviously-fake `example/` vendor prefix, and the key is an
/// obviously-fake placeholder — no live network call is made anywhere
/// in this file (the stand-in server is the loopback `LoopbackServer`,
/// the same local helper the other provider tests use). `collect`,
/// `sse`, `Recorder` and `closedPort` come from ProviderTests.swift.
@Suite struct OpenRouterProviderTests {
    /// A recorded sample `/models` payload. Four listable models plus
    /// one entry with no `id`, which parsing must skip.
    static let modelsFixture = Data("""
        {"data":[
          {"id":"example/test-model-alpha","name":"Test Model Alpha","description":"A fake model for tests.",
           "context_length":128000,"pricing":{"prompt":"0","completion":"0"},
           "supported_parameters":["tools","temperature","max_tokens"]},
          {"id":"example/test-model-beta","description":"No display name and no tool-calling field.",
           "context_length":200000},
          {"id":"example/test-model-gamma","name":"Test Model Gamma",
           "supported_parameters":["temperature","top_p"]},
          {"id":"example/test-model-delta","name":"Test Model Delta","context_length":32768,
           "supported_parameters":[]},
          {"name":"No identifier at all","context_length":4096}
        ]}
        """.utf8)

    static let fakeKey = "fake-test-key"

    @Test func parsesRecordedModelsPayload() {
        let models = OpenRouterProvider.parseModels(Self.modelsFixture)
        #expect(models.map(\.id) == ["example/test-model-alpha", "example/test-model-beta",
                                     "example/test-model-gamma", "example/test-model-delta"])
        #expect(models[0] == ModelInfo(id: "example/test-model-alpha", displayName: "Test Model Alpha", contextWindow: 128000))
        // No `name`: the display name falls back to the id.
        #expect(models[1] == ModelInfo(id: "example/test-model-beta", displayName: "example/test-model-beta", contextWindow: 200000))
        // No `context_length`: no context window, not a guessed default.
        #expect(models[2] == ModelInfo(id: "example/test-model-gamma", displayName: "Test Model Gamma", contextWindow: nil))
        #expect(models[3].contextWindow == 32768)
        #expect(OpenRouterProvider.parseModels(Data("{}".utf8)).isEmpty)
        #expect(OpenRouterProvider.parseModels(Data("not json".utf8)).isEmpty)
    }

    @Test func toolCallingSupportFromRecordedPayload() {
        #expect(OpenRouterProvider.toolCallingSupport(for: "example/test-model-alpha", in: Self.modelsFixture) == .supports)
        // `supported_parameters` present without "tools".
        #expect(OpenRouterProvider.toolCallingSupport(for: "example/test-model-gamma", in: Self.modelsFixture) == .doesNotSupport)
        #expect(OpenRouterProvider.toolCallingSupport(for: "example/test-model-delta", in: Self.modelsFixture) == .doesNotSupport)
        // No `supported_parameters` field at all: unknown, not a failure.
        #expect(OpenRouterProvider.toolCallingSupport(for: "example/test-model-beta", in: Self.modelsFixture) == .unknown)
        // Not listed: nil (the caller turns this into `.modelNotFound`).
        #expect(OpenRouterProvider.toolCallingSupport(for: "example/not-listed", in: Self.modelsFixture) == nil)
    }

    @Test func availabilityNeedsAKey() async {
        for key in [nil, "", "   "] as [String?] {
            guard case .signedOut(let hint) = await OpenRouterProvider(apiKey: key).availability() else {
                Issue.record("expected signedOut for key \(String(describing: key))"); return
            }
            #expect(hint.contains("OpenRouter API key"))
        }
    }

    @Test func availabilityListsModelsSendsBearerAndCaches() async throws {
        let rec = Recorder()
        let hits = HitCounter()
        let server = try LoopbackServer { req in
            rec.add(req)
            guard req.path == "/v1/models" else { return .text("", status: 404) }
            // First fetch lists one model; later fetches list another, so
            // the test can tell a cached answer from a fresh one.
            return hits.next() == 1
                ? .json(["data": [["id": "example/test-model-alpha", "name": "Test Model Alpha", "context_length": 128000]]])
                : .json(["data": [["id": "example/test-model-beta", "name": "Test Model Beta", "context_length": 200000]]])
        }
        let p = OpenRouterProvider(baseURL: server.baseURL + "/v1", apiKey: Self.fakeKey)
        let a = await p.availability()
        #expect(a.models == [ModelInfo(id: "example/test-model-alpha", displayName: "Test Model Alpha", contextWindow: 128000)])
        #expect(rec.requests.first?.header("authorization") == "Bearer \(Self.fakeKey)")
        #expect(hits.hits == 1)
        // Second call is served from the 1-hour cache: no second request.
        #expect(await p.availability().models.map(\.id) == ["example/test-model-alpha"])
        #expect(hits.hits == 1)
        #expect(await p.contextWindow(model: "example/test-model-alpha") == 128000)
        #expect(hits.hits == 1)
        // Manual refresh bypasses the cache and sees the new listing.
        #expect(try await p.refreshModels().map(\.id) == ["example/test-model-beta"])
        #expect(hits.hits == 2)
        #expect(try await p.testConnection() == "Connected to OpenRouter (1 models available).")
    }

    @Test func availabilityMapsAuthAndBillingFailures() async throws {
        let unauthorized = try LoopbackServer { _ in .json(["error": ["message": "Unauthorized", "code": 401]], status: 401) }
        guard case .signedOut(let hint) = await OpenRouterProvider(baseURL: unauthorized.baseURL, apiKey: Self.fakeKey).availability() else {
            Issue.record("expected signedOut on 401"); return
        }
        #expect(hint.contains("not accepted"))

        let noCredits = try LoopbackServer { _ in .json(["error": ["message": "Insufficient credits.", "code": 402]], status: 402) }
        guard case .failed(let message) = await OpenRouterProvider(baseURL: noCredits.baseURL, apiKey: Self.fakeKey).availability() else {
            Issue.record("expected failed on 402"); return
        }
        #expect(message.contains("Insufficient credits"))

        let limited = try LoopbackServer { _ in .json(["error": ["message": "Rate limited.", "code": 429]], status: 429) }
        guard case .failed(let message) = await OpenRouterProvider(baseURL: limited.baseURL, apiKey: Self.fakeKey).availability() else {
            Issue.record("expected failed on 429"); return
        }
        #expect(message.contains("Rate limited"))

        guard case .notRunning = await OpenRouterProvider(baseURL: try closedPort(), apiKey: Self.fakeKey).availability() else {
            Issue.record("expected notRunning on a closed port"); return
        }
    }

    @Test func validateModelChecksShapeListAndToolSupport() async throws {
        let server = try LoopbackServer { req in
            req.path == "/v1/models" ? .init(status: 200, contentType: "application/json", body: Self.modelsFixture) : .text("", status: 404)
        }
        let p = OpenRouterProvider(baseURL: server.baseURL + "/v1", apiKey: Self.fakeKey)
        #expect(try await p.validateModel("example/test-model-alpha") == .supports)
        #expect(try await p.validateModel("example/test-model-beta") == .unknown)
        #expect(try await p.validateModel("example/test-model-gamma") == .doesNotSupport)
        await #expect(throws: AssistantError.modelNotFound(
            model: "example/not-listed",
            hint: "Choose another model from the discovered list in Settings ▸ Coding Assistant.")) {
            try await p.validateModel("example/not-listed")
        }
        // No provider/model slash: not an OpenRouter identifier at all.
        await #expect(throws: AssistantError.self) { try await p.validateModel("bare-model-name") }
    }

    @Test func streamsChatCompletionsWithBearerAndUsage() async throws {
        let rec = Recorder()
        let server = try LoopbackServer { req in
            rec.add(req)
            switch req.path {
            case "/v1/models":
                return .json(["data": [["id": "example/test-model-alpha", "name": "Test Model Alpha", "context_length": 128000]]])
            case "/v1/chat/completions":
                guard req.header("authorization") == "Bearer \(Self.fakeKey)" else {
                    return .json(["error": ["message": "bad key", "code": 401]], status: 401)
                }
                return .init(contentType: "text/event-stream", chunks: sse([
                    ["choices": [["index": 0, "delta": ["role": "assistant"]]]],
                    ["choices": [["index": 0, "delta": ["content": "Hi"]]]],
                    ["choices": [["index": 0, "delta": ["content": " there"]]]],
                    ["choices": [["index": 0, "delta": [String: Any](), "finish_reason": "stop"]],
                     "usage": ["prompt_tokens": 5, "completion_tokens": 2]],
                    "[DONE]",
                ]), delay: 0.01)
            default:
                return .text("", status: 404)
            }
        }
        let p = OpenRouterProvider(baseURL: server.baseURL + "/v1", apiKey: Self.fakeKey)
        let r = try await collect(p.send(ChatRequest(model: "example/test-model-alpha", instructions: "sys",
                                                     messages: [ChatMessage(.user, "hello")])))
        #expect(r.text == "Hi there")
        #expect(r.events.last == .finished(TokenUsage(inputTokens: 5, outputTokens: 2)))
        let chat = try #require(rec.requests.first { $0.path == "/v1/chat/completions" })
        let body = try #require(JSON.object(chat.body))
        #expect(body["model"] as? String == "example/test-model-alpha")
        #expect(body["stream"] as? Bool == true)
        #expect((body["messages"] as? [[String: String]])?.map { $0["role"]! } == ["system", "user"])
        #expect((body["messages"] as? [[String: String]])?.first?["content"] == "sys")
    }

    @Test func sendMapsErrorsAndReportsTruncation() async throws {
        let notFound = try LoopbackServer { _ in
            .json(["error": ["message": "No endpoints found for example/not-listed.", "code": 404]], status: 404)
        }
        await #expect(throws: AssistantError.modelNotFound(
            model: "example/not-listed",
            hint: "Choose another model from the discovered list in Settings ▸ Coding Assistant.")) {
            _ = try await collect(OpenRouterProvider(baseURL: notFound.baseURL, apiKey: Self.fakeKey)
                .send(ChatRequest(model: "example/not-listed", instructions: "", messages: [])))
        }
        let truncated = try LoopbackServer { _ in
            .init(contentType: "text/event-stream", chunks: sse([
                ["choices": [["delta": ["content": "a"], "finish_reason": "length"]]],
                ["choices": [["delta": [String: Any](), "finish_reason": "stop"]]],
                "[DONE]",
            ]))
        }
        let r = try await collect(OpenRouterProvider(baseURL: truncated.baseURL, apiKey: Self.fakeKey)
            .send(ChatRequest(model: "example/test-model-alpha", instructions: "", messages: [])))
        #expect(r.events.contains(.truncated))
        #expect(r.events.last == .finished(nil))
        await #expect(throws: AssistantError.notSignedIn(hint: OpenRouterProvider.signedOutHint)) {
            _ = try await collect(OpenRouterProvider(apiKey: nil)
                .send(ChatRequest(model: "example/test-model-alpha", instructions: "", messages: [])))
        }
    }

    @Test func errorMappingIsPure() {
        #expect(OpenRouterProvider.mapError(status: 401, body: Data(#"{"error":{"message":"bad key"}}"#.utf8), model: "")
                == .notSignedIn(hint: "The OpenRouter API key was not accepted. Check it in Settings ▸ Coding Assistant."))
        #expect(OpenRouterProvider.mapError(status: 402, body: Data(#"{"error":{"message":""}}"#.utf8), model: "")
                == .failed("OpenRouter reports insufficient credits (402) for this account. Add credits on openrouter.ai; the selected model was not changed."))
        #expect(OpenRouterProvider.mapError(status: 429, body: Data(#"{"error":{"message":"slow down"}}"#.utf8), model: "")
                == .usageLimit("slow down"))
        // A 404 that does not name the model is a plain HTTP error, not a
        // model error (e.g. a wrong base URL).
        #expect(OpenRouterProvider.mapError(status: 404, body: Data(#"{"error":{"message":"not found"}}"#.utf8),
                                           model: "example/test-model-alpha")
                == .http(status: 404, message: "not found"))
        #expect(OpenRouterProvider.mapError(status: 500, body: Data(#"{"error":{"message":"boom"}}"#.utf8), model: "")
                == .http(status: 500, message: "boom"))
    }
}

/// A thread-safe request count for stand-in servers.
final class HitCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var hits: Int { lock.lock(); defer { lock.unlock() }; return count }
}
