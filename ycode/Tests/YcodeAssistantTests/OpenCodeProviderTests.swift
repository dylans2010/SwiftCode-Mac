import Foundation
import Testing
@testable import YcodeAssistant

/// Fixture model ids are invented ("acme/alpha") — no real provider or
/// model is named here, so nothing can be mistaken for a catalog.

@Suite struct OpenCodeProviderTests {
    @Test func parseModelsHandlesEveryCatalogShape() {
        // `providers` array, `id` keys.
        let arrayShape = Data("""
            {"providers": [
                {"id": "acme", "models": [{"id": "beta"}, {"id": "alpha"}]},
                {"id": "other", "models": [{"modelID": "gamma"}]}
            ]}
            """.utf8)
        #expect(OpenCodeProvider.parseModels(arrayShape).map(\.id) == [
            "opencode:acme/alpha", "opencode:acme/beta", "opencode:other/gamma",
        ])
        #expect(OpenCodeProvider.parseModels(arrayShape).map(\.displayName) == [
            "acme/alpha", "acme/beta", "other/gamma",
        ])

        // Provider-keyed object.
        let keyedShape = Data("""
            {"acme": {"models": [{"id": "alpha"}]}, "other": {"models": [{"id": "gamma"}]}}
            """.utf8)
        #expect(OpenCodeProvider.parseModels(keyedShape).map(\.id) == [
            "opencode:acme/alpha", "opencode:other/gamma",
        ])

        // Models as a dictionary, plus duplicates and junk that must be
        // skipped, never fabricated into a model.
        let dictShape = Data("""
            {"providers": [{"id": "acme", "models": {
                "alpha": {}, "beta": {"modelID": "beta"}, "alpha2": {"id": "alpha"}
            }}, {"models": [{"id": "x"}]}, {"id": "", "models": [{"id": "y"}]},
            {"id": "acme", "models": [{"id": ""}, {}]}]}
            """.utf8)
        #expect(OpenCodeProvider.parseModels(dictShape).map(\.id) == [
            "opencode:acme/alpha", "opencode:acme/beta",
        ])

        // Unparseable or empty bodies are an empty list, not a fallback.
        #expect(OpenCodeProvider.parseModels(Data("not json".utf8)) == [])
        #expect(OpenCodeProvider.parseModels(Data("{}".utf8)) == [])
        #expect(OpenCodeProvider.parseModels(Data("{\"providers\": []}".utf8)) == [])
    }

    @Test func parseStoredID() {
        #expect(OpenCodeProvider.parseStoredID("opencode:acme/alpha") == OpenCodeModelID(providerID: "acme", modelID: "alpha"))
        #expect(OpenCodeProvider.parseStoredID("acme/alpha") == OpenCodeModelID(providerID: "acme", modelID: "alpha"))
        // A model id may itself contain a slash; only the first splits.
        #expect(OpenCodeProvider.parseStoredID("opencode:acme/a/b") == OpenCodeModelID(providerID: "acme", modelID: "a/b"))
        #expect(OpenCodeProvider.parseStoredID(nil) == nil)
        #expect(OpenCodeProvider.parseStoredID("") == nil)
        #expect(OpenCodeProvider.parseStoredID("opencode:") == nil)
        #expect(OpenCodeProvider.parseStoredID("opencode:acme") == nil)
        #expect(OpenCodeProvider.parseStoredID("opencode:/alpha") == nil)
        #expect(OpenCodeProvider.parseStoredID("plain-model") == nil)
    }

    @Test func parseEventFrames() {
        let delta = #"{"type":"message.part.delta","properties":{"sessionID":"s1","part":{"type":"text","text":"Hel"}}}"#
        #expect(OpenCodeProvider.parseEvent(delta)?.event == .text("Hel"))
        #expect(OpenCodeProvider.parseEvent(delta)?.sessionID == "s1")

        // The bare `delta` string form.
        let bare = #"{"type":"message.part.delta","properties":{"sessionID":"s1","delta":"lo"}}"#
        #expect(OpenCodeProvider.parseEvent(bare)?.event == .text("lo"))

        // Tool parts fail closed; text `updated` frames are ignored
        // (they carry the full part, not a delta).
        let tool = #"{"type":"message.part.delta","properties":{"sessionID":"s1","part":{"type":"tool"}}}"#
        #expect(OpenCodeProvider.parseEvent(tool)?.event == .tool)
        let updated = #"{"type":"message.part.updated","properties":{"sessionID":"s1","part":{"type":"text","text":"Hello"}}}"#
        #expect(OpenCodeProvider.parseEvent(updated)?.event == .ignored)
        let updatedTool = #"{"type":"message.part.updated","properties":{"sessionID":"s1","part":{"type":"tool"}}}"#
        #expect(OpenCodeProvider.parseEvent(updatedTool)?.event == .tool)

        let idle = #"{"type":"session.idle","properties":{"sessionID":"s1"}}"#
        #expect(OpenCodeProvider.parseEvent(idle)?.event == .idle)
        let err = #"{"type":"session.error","properties":{"sessionID":"s1","error":{"message":"boom"}}}"#
        #expect(OpenCodeProvider.parseEvent(err)?.event == .error("boom"))
        let errPlain = #"{"type":"session.error","properties":{"message":"plain"}}"#
        #expect(OpenCodeProvider.parseEvent(errPlain)?.event == .error("plain"))

        // Unknown types, [DONE], and non-JSON are ignored, never text.
        #expect(OpenCodeProvider.parseEvent(#"{"type":"session.created","properties":{}}"#)?.event == .ignored)
        #expect(OpenCodeProvider.parseEvent("[DONE]") == nil)
        #expect(OpenCodeProvider.parseEvent("") == nil)
        #expect(OpenCodeProvider.parseEvent("not json") == nil)

        // Alternate session-id spellings.
        #expect(OpenCodeProvider.parseEvent(#"{"type":"session.idle","properties":{"sessionId":"s9"}}"#)?.sessionID == "s9")
        #expect(OpenCodeProvider.parseEvent(#"{"type":"session.idle","properties":{"session_id":"s8"}}"#)?.sessionID == "s8")
    }

    @Test func promptBodyMapping() {
        let req = ChatRequest(model: "opencode:acme/alpha", instructions: "Be brief.",
                              messages: [ChatMessage(.user, "Hi")])
        let body = OpenCodeProvider.promptBody(req, model: OpenCodeModelID(providerID: "acme", modelID: "alpha"), agent: "swiftcode")
        #expect((body["model"] as? [String: String]) == ["providerID": "acme", "modelID": "alpha"])
        #expect(body["agent"] as? String == "swiftcode")
        #expect(body["system"] as? String == "Be brief.")
        let parts = body["parts"] as? [[String: String]]
        #expect(parts == [["type": "text", "text": "<user>\nHi\n</user>"]])
        // Generation options are never sent (Legacy never sent them).
        #expect(body["temperature"] == nil && body["max_tokens"] == nil)
    }

    @Test func contextWindowIsLegacyDefault() async {
        #expect(await OpenCodeProvider().contextWindow(model: "opencode:acme/alpha") == 128_000)
        #expect(OpenCodeProvider.defaultBaseURL == "http://127.0.0.1:4096")
        #expect(OpenCodeProvider().endpointURL("session", directory: "/tmp/w")?.absoluteString.hasSuffix("/session?directory=/tmp/w") == true)
    }

    @Test func availabilityAndModelCache() async throws {
        final class Hits: @unchecked Sendable {
            private let lock = NSLock()
            private var n = 0
            func add() { lock.lock(); n += 1; lock.unlock() }
            var count: Int { lock.lock(); defer { lock.unlock() }; return n }
        }
        let hits = Hits()
        let server = try LoopbackServer { req in
            hits.add()
            return .json(["providers": [["id": "acme", "models": [["id": "beta"], ["id": "alpha"]]]]])
        }
        let p = OpenCodeProvider(baseURL: server.baseURL)
        let a = await p.availability()
        #expect(a.models.map(\.id) == ["opencode:acme/alpha", "opencode:acme/beta"])
        #expect(hits.count == 1)
        // Within the TTL the cached list is reused without a request.
        _ = await p.availability()
        #expect(hits.count == 1)
        // A manual refresh clears the cache, so the next check refetches.
        p.refreshModels()
        _ = await p.availability()
        #expect(hits.count == 2)

        let empty = try LoopbackServer { _ in .json(["providers": []]) }
        guard case .noModels(let hint) = await OpenCodeProvider(baseURL: empty.baseURL).availability() else {
            Issue.record("expected noModels"); return
        }
        #expect(hint.contains("Configure a model provider"))

        let auth = try LoopbackServer { _ in .text("unauthorized", status: 401) }
        guard case .failed(let m) = await OpenCodeProvider(baseURL: auth.baseURL).availability() else {
            Issue.record("expected failed on 401"); return
        }
        #expect(m.contains("authentication"))

        guard case .notRunning(let h) = await OpenCodeProvider(baseURL: try closedPort()).availability() else {
            Issue.record("expected notRunning"); return
        }
        #expect(h.contains("opencode serve"))
    }

    @Test func streamsSessionFlow() async throws {
        let rec = Recorder()
        let server = try LoopbackServer { req in
            rec.add(req)
            switch req.path {
            case "/session":
                return .json(["id": "s1"])
            case "/event":
                return .init(contentType: "text/event-stream", chunks: sse([
                    ["type": "message.part.delta", "properties": ["sessionID": "other", "part": ["type": "text", "text": "WRONG"]]],
                    ["type": "message.part.delta", "properties": ["sessionID": "s1", "part": ["type": "text", "text": "Hel"]]],
                    ["type": "message.part.delta", "properties": ["sessionID": "s1", "part": ["type": "text", "text": "lo"]]],
                    ["type": "session.idle", "properties": ["sessionID": "s1"]],
                ]), delay: 0.01)
            case "/session/s1/prompt_async":
                return .json([String: Any]())
            default:
                return .text("", status: 404)
            }
        }
        let r = try await collect(OpenCodeProvider(baseURL: server.baseURL).send(
            ChatRequest(model: "opencode:acme/alpha", instructions: "Be brief.", messages: [ChatMessage(.user, "Hi")],
                        workingDirectory: URL(fileURLWithPath: "/tmp"))))
        // Events for another session are ignored; the run ends finished.
        #expect(r.text == "Hello")
        #expect(r.events.last == .finished(nil))
        // Subscribe-first order: session, event feed, then the prompt.
        #expect(rec.requests.map(\.path) == ["/session", "/event", "/session/s1/prompt_async"])
        let prompt = try #require(rec.requests.first { $0.path.hasSuffix("prompt_async") })
        #expect(prompt.query["directory"] == "/tmp")
        let body = try #require(JSON.object(prompt.body))
        #expect((body["model"] as? [String: String]) == ["providerID": "acme", "modelID": "alpha"])
        #expect(body["agent"] as? String == "swiftcode")
        #expect(body["system"] as? String == "Be brief.")
        let sessionReq = try #require(rec.requests.first { $0.path == "/session" })
        #expect(JSON.object(sessionReq.body)?["title"] as? String == "SwiftCode Assist")
    }

    @Test func toolPartFailsClosed() async throws {
        let server = try LoopbackServer { req in
            switch req.path {
            case "/session": return .json(["id": "s1"])
            case "/event":
                return .init(contentType: "text/event-stream", chunks: sse([
                    ["type": "message.part.delta", "properties": ["sessionID": "s1", "part": ["type": "tool"]]],
                ]), delay: 0.01)
            case "/session/s1/prompt_async": return .json([String: Any]())
            default: return .text("", status: 404)
            }
        }
        await #expect(throws: AssistantError.failed(
            "OpenCode attempted to execute a tool on a Ycode session. " +
            "Configure the `swiftcode` agent on the server with every permission " +
            "denied (see Settings ▸ Coding Assistant ▸ OpenCode), then retry. The run was aborted.")) {
            _ = try await collect(OpenCodeProvider(baseURL: server.baseURL).send(
                ChatRequest(model: "opencode:acme/alpha", instructions: "", messages: [ChatMessage(.user, "x")])))
        }
    }

    @Test func staleSessionRetriesOnce() async throws {
        final class State: @unchecked Sendable {
            private let lock = NSLock()
            private var sessions = 0
            private var prompts = 0
            func nextSession() -> String { lock.lock(); defer { lock.unlock() }; sessions += 1; return "s\(sessions)" }
            func nextPrompt() -> Int { lock.lock(); defer { lock.unlock() }; prompts += 1; return prompts }
        }
        let state = State()
        let server = try LoopbackServer { req in
            switch req.path {
            case "/session":
                return .json(["id": state.nextSession()])
            case "/event":
                // The single subscription survives the retry; events
                // carry the final session id.
                return .init(contentType: "text/event-stream", chunks: sse([
                    ["type": "message.part.delta", "properties": ["sessionID": "s2", "part": ["type": "text", "text": "ok"]]],
                    ["type": "session.idle", "properties": ["sessionID": "s2"]],
                ]), delay: 0.01)
            case "/session/s1/prompt_async":
                _ = state.nextPrompt()
                return .text("session not found", status: 404)
            case "/session/s2/prompt_async":
                _ = state.nextPrompt()
                return .json([String: Any]())
            default:
                return .text("", status: 404)
            }
        }
        let r = try await collect(OpenCodeProvider(baseURL: server.baseURL).send(
            ChatRequest(model: "opencode:acme/alpha", instructions: "", messages: [ChatMessage(.user, "x")])))
        #expect(r.text == "ok")
        #expect(r.events.last == .finished(nil))
    }

    @Test func missingModelAndUnreachable() async throws {
        await #expect(throws: AssistantError.modelNotFound(
            model: "", hint: "Choose an OpenCode model in Settings ▸ Coding Assistant.")) {
            _ = try await collect(OpenCodeProvider().send(
                ChatRequest(model: nil, instructions: "", messages: [ChatMessage(.user, "x")])))
        }
        await #expect(throws: AssistantError.self) {
            _ = try await collect(OpenCodeProvider(baseURL: try closedPort()).send(
                ChatRequest(model: "opencode:acme/alpha", instructions: "", messages: [ChatMessage(.user, "x")])))
        }
    }
}
