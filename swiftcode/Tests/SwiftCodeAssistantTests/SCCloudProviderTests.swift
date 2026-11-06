import Foundation
import Testing
@testable import SwiftCodeAssistant

/// SCCloud: SwiftCode's own hosted models against a configurable endpoint.
/// All network traffic here goes to a loopback stand-in server, never to a
/// real endpoint — the Legacy endpoint is dead and no default is shipped.
/// Fixture values are obviously fake (`ssc_test-…`, `https://sccloud.example.invalid`).
@Suite struct SCCloudProviderTests {
    /// An obviously-fake device fingerprint, used only as a fixture.
    static let fakeFingerprint = "ssc_test-fingerprint-for-unit-tests-only"

    @Test func unconfiguredReportsHonestUnavailability() async {
        let p = SCCloudProvider()
        #expect(p.baseURL.isEmpty)
        #expect(!p.isConfigured)
        guard case .signedOut(let hint) = await p.availability() else { Issue.record("expected signedOut"); return }
        #expect(hint.contains("endpoint URL"))
        #expect(hint.contains("Settings"))

        // A non-URL and a non-HTTPS, non-loopback URL are equally unconfigured.
        #expect(!SCCloudProvider(baseURL: "not a url").isConfigured)
        #expect(!SCCloudProvider(baseURL: "ftp://sccloud.example.invalid").isConfigured)
        // A well-formed HTTPS URL counts as configured even though nothing
        // answers there — availability then reports it as not running.
        #expect(SCCloudProvider(baseURL: "https://sccloud.example.invalid").isConfigured)
        guard case .notRunning(let hint) = await SCCloudProvider(baseURL: "https://sccloud.example.invalid").availability() else {
            Issue.record("expected notRunning for an unreachable configured endpoint"); return
        }
        #expect(hint.contains("SCCloud endpoint"))
    }

    @Test func sendWithoutEndpointThrowsNotSignedIn() async {
        await #expect(throws: AssistantError.notSignedIn(hint: SCCloudProvider.unconfiguredHint)) {
            _ = try await collect(SCCloudProvider().send(ChatRequest(model: nil, instructions: "", messages: [ChatMessage(.user, "hi")])))
        }
    }

    @Test func discoveryParsingCanonicalizesDedupesAndSorts() {
        let body = Data(#"{"object":"list","data":[{"id":"zeta:latest","owned_by":"swiftcode"},{"id":"alpha"},{"id":"zeta"},{"id":"beta:7b","owned_by":"x"},{"id":""},{"id":42}]}"#.utf8)
        #expect(SCCloudProvider.parseModels(body) == [
            ModelInfo(id: "alpha", displayName: "alpha"),
            ModelInfo(id: "beta:7b", displayName: "beta:7b"),
            ModelInfo(id: "zeta", displayName: "zeta"),
        ])
        #expect(SCCloudProvider.parseModels(Data("not json".utf8)) == [])
        #expect(SCCloudProvider.parseModels(Data(#"{"data":[]}"#.utf8)) == [])
        #expect(SCCloudProvider.canonicalModelName("acme:latest") == "acme")
        #expect(SCCloudProvider.canonicalModelName("acme-coder:7b") == "acme-coder:7b")
    }

    @Test func internalIDUnwrapping() {
        #expect(SCCloudProvider.endpointName(forInternalID: "swiftcode-cloud:acme:8b") == "acme:8b")
        #expect(SCCloudProvider.endpointName(forInternalID: "swiftcode-cloud:acme:latest") == "acme")
        #expect(SCCloudProvider.endpointName(forInternalID: "swiftcode-cloud") == nil)
        #expect(SCCloudProvider.endpointName(forInternalID: "other-provider-model") == nil)
    }

    @Test func responseParsingAcceptsLegacyShapes() throws {
        let choices = Data(#"{"choices":[{"message":{"role":"assistant","content":"Hello there"}}]}"#.utf8)
        #expect(try SCCloudProvider.parseResponse(choices) == "Hello there")
        let ollama = Data(#"{"message":{"role":"assistant","content":"Hi from Ollama"}}"#.utf8)
        #expect(try SCCloudProvider.parseResponse(ollama) == "Hi from Ollama")
        let single = Data(#"{"response":"just the text"}"#.utf8)
        #expect(try SCCloudProvider.parseResponse(single) == "just the text")
        #expect(try SCCloudProvider.parseResponse(Data("bare string body".utf8)) == "bare string body")
        #expect(throws: AssistantError.self) { _ = try SCCloudProvider.parseResponse(Data(#"{"choices":[]}"#.utf8)) }
        #expect(throws: AssistantError.self) { _ = try SCCloudProvider.parseResponse(Data()) }
    }

    @Test func fingerprintProvisioningShape() {
        let f = SCCloudProvider.provisionFingerprint()
        #expect(f.hasPrefix("ssc_"))
        let hex = f.dropFirst("ssc_".count)
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { $0.isHexDigit })
        #expect(SCCloudProvider.provisionFingerprint() != f)
    }

    @Test func rateLimiterGatesAfterTheLimit() {
        let limiter = SCCloudRateLimiter(limit: 2, window: 60)
        #expect(limiter.checkGate().allowed)
        limiter.recordRequest()
        #expect(limiter.checkGate().remaining == 1)
        limiter.recordRequest()
        let gate = limiter.checkGate()
        #expect(!gate.allowed)
        #expect(gate.remaining == 0)
        #expect(gate.retryAfter != nil)
        #expect(SCCloudRateLimiter.formatDuration(60 * 60 * 7 + 60 * 12) == "7h 12m")
        #expect(SCCloudRateLimiter.formatDuration(60 * 5) == "5m")
    }

    @Test func discoveryAndChatAgainstFakeEndpoint() async throws {
        let rec = Recorder()
        let server = try LoopbackServer { req in
            rec.add(req)
            switch req.path {
            case "/v1/models":
                return .json(["object": "list", "data": [["id": "beta:latest", "owned_by": "swiftcode"], ["id": "alpha", "context_window": 8192]]])
            case "/v1/chat/completions":
                return .json(["choices": [["message": ["role": "assistant", "content": "Hello from SCCloud"]]]])
            default:
                return .text("", status: 404)
            }
        }
        let p = SCCloudProvider(baseURL: server.baseURL, fingerprint: Self.fakeFingerprint)
        let a = await p.availability()
        #expect(a.models.map(\.id) == ["alpha", "beta"])
        #expect(await p.contextWindow(model: "alpha") == 8192)
        #expect(await p.contextWindow(model: "beta") == nil)

        let r = try await collect(p.send(ChatRequest(model: "alpha", instructions: "Be brief.", messages: [ChatMessage(.user, "Hi")])))
        #expect(r.text == "Hello from SCCloud")
        #expect(r.events.last == .finished(nil))

        let modelsReq = try #require(rec.requests.first { $0.path == "/v1/models" })
        #expect(modelsReq.header("x-swiftcode-device-fingerprint") == Self.fakeFingerprint)
        #expect(modelsReq.header("authorization") == nil)
        let chat = try #require(rec.requests.first { $0.path == "/v1/chat/completions" })
        #expect(chat.header("x-swiftcode-device-fingerprint") == Self.fakeFingerprint)
        #expect(chat.header("authorization") == nil)
        let body = try #require(JSON.object(chat.body))
        #expect(body["model"] as? String == "alpha")
        #expect(body["stream"] as? Bool == false)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"]! } == ["system", "user"])
        #expect(messages.first?["content"]?.string == "Be brief.")
    }

    @Test func legacyInternalIDIsUnwrappedOnSend() async throws {
        let server = try LoopbackServer { req in
            req.path == "/v1/models" ? .json(["object": "list", "data": [["id": "alpha"]]])
                : .json(["choices": [["message": ["role": "assistant", "content": "ok"]]]])
        }
        let p = SCCloudProvider(baseURL: server.baseURL, fingerprint: Self.fakeFingerprint)
        let r = try await collect(p.send(ChatRequest(model: "swiftcode-cloud:alpha:latest", instructions: "", messages: [ChatMessage(.user, "x")])))
        #expect(r.text == "ok")
    }

    @Test func sendUsesFirstDiscoveredModelWhenNoneSelected() async throws {
        let rec = Recorder()
        let server = try LoopbackServer { req in
            rec.add(req)
            return req.path == "/v1/models"
                ? .json(["object": "list", "data": [["id": "alpha"], ["id": "beta"]]])
                : .json(["choices": [["message": ["role": "assistant", "content": "first model"]]]])
        }
        let p = SCCloudProvider(baseURL: server.baseURL, fingerprint: Self.fakeFingerprint)
        let r = try await collect(p.send(ChatRequest(model: nil, instructions: "", messages: [ChatMessage(.user, "x")])))
        #expect(r.text == "first model")
        let chat = try #require(rec.requests.first { $0.path == "/v1/chat/completions" })
        #expect(JSON.object(chat.body)?["model"] as? String == "alpha")
    }

    @Test func httpErrorsMapHonestly() async throws {
        let tooMany = try LoopbackServer { req in
            req.path == "/v1/models" ? .json(["object": "list", "data": [["id": "alpha"]]]) : .text("slow down", status: 429)
        }
        await #expect(throws: AssistantError.usageLimit("SwiftCode Cloud reported its rate limit. Try again later.")) {
            _ = try await collect(SCCloudProvider(baseURL: tooMany.baseURL, fingerprint: Self.fakeFingerprint)
                .send(ChatRequest(model: "alpha", instructions: "", messages: [ChatMessage(.user, "x")])))
        }

        let tunnelDown = try LoopbackServer { _ in .text("<html><body>Error 1033</body></html>", status: 530) }
        await #expect(throws: AssistantError.temporarilyUnavailable("The SwiftCode Cloud model server is currently offline or unreachable (tunnel error). Please try again later or select another model in Settings ▸ Coding Assistant.")) {
            _ = try await collect(SCCloudProvider(baseURL: tunnelDown.baseURL, fingerprint: Self.fakeFingerprint)
                .send(ChatRequest(model: "alpha", instructions: "", messages: [ChatMessage(.user, "x")])))
        }
    }

    @Test func localQuotaBlocksBeforeNetwork() async throws {
        let limiter = SCCloudRateLimiter(limit: 1, window: 60)
        limiter.recordRequest()
        let server = try LoopbackServer { _ in .json(["choices": [["message": ["role": "assistant", "content": "nope"]]]]) }
        await #expect(throws: AssistantError.self) {
            _ = try await collect(SCCloudProvider(baseURL: server.baseURL, fingerprint: Self.fakeFingerprint, limiter: limiter)
                .send(ChatRequest(model: "alpha", instructions: "", messages: [ChatMessage(.user, "x")])))
        }
    }
}
