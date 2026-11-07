import Foundation
import Testing
@testable import YcodeAssistant

@Suite struct LLMWiringGapTests {
    struct StubProvider: AssistantProvider {
        var kind: ProviderKind
        var text: String
        var truncated: Bool = false
        func availability() async -> ProviderAvailability {
            .ready([ModelInfo(id: "stub/model", displayName: "Stub")])
        }
        func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
            let text = text, truncated = truncated
            return AsyncThrowingStream { continuation in
                let half = text.index(text.startIndex, offsetBy: text.count / 2)
                if !text.isEmpty {
                    continuation.yield(.text(String(text[..<half])))
                    continuation.yield(.text(String(text[half...])))
                }
                if truncated { continuation.yield(.truncated) }
                continuation.yield(.finished(nil))
                continuation.finish()
            }
        }
    }

    struct FailingProvider: AssistantProvider {
        var kind: ProviderKind
        var message: String = "boom"
        func availability() async -> ProviderAvailability { .ready([]) }
        func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
            let message = message
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AssistantError.failed(message))
            }
        }
    }

    func settings(provider: ProviderKind, model: String? = nil) -> AssistantSettings {
        var s = AssistantSettings()
        s.provider = provider
        if let model { s.setModel(model, for: provider) }
        return s
    }

    func service(_ settings: AssistantSettings,
                 overrides: [ProviderKind: AssistantProvider] = [:]) -> LLMToolCompletionService {
        LLMToolCompletionService(
            backends: AssistantBackends(settings: settings, store: MemorySecretStore(), account: nil),
            providerOverrides: overrides)
    }

    @Test func resolvesStoredOpenRouterModel() async throws {
        let svc = service(settings(provider: .openRouter, model: "openai/gpt-4o-mini"),
                          overrides: [.openRouter: StubProvider(kind: .openRouter, text: "ok")])
        let resolved = try svc.resolve()
        #expect(resolved.kind == .openRouter)
        #expect(resolved.model == "openai/gpt-4o-mini")
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.text == "ok")
        #expect(completion.provider == .openRouter)
        #expect(completion.model == "openai/gpt-4o-mini")
        #expect(!completion.truncated)
    }

    @Test func resolvesHermesPrefixedID() async throws {
        let svc = service(settings(provider: .hermes, model: "hermes:qwen3"),
                          overrides: [.hermes: StubProvider(kind: .hermes, text: "hermes-ok")])
        let resolved = try svc.resolve()
        #expect(resolved.kind == .hermes)
        #expect(resolved.model == "hermes:qwen3")
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.provider == .hermes)
        #expect(completion.text == "hermes-ok")
    }

    @Test func resolvesOpenCodePrefixedID() async throws {
        let svc = service(settings(provider: .openCode, model: "opencode:anthropic/claude-sonnet-4-5"),
                          overrides: [.openCode: StubProvider(kind: .openCode, text: "opencode-ok")])
        let resolved = try svc.resolve()
        #expect(resolved.kind == .openCode)
        #expect(resolved.model == "opencode:anthropic/claude-sonnet-4-5")
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.provider == .openCode)
    }

    @Test func resolvesCloudModelViaToggle() async throws {
        var s = settings(provider: .openRouter, model: "openai/gpt-4o-mini")
        s.useSwiftCodeCloudModel = true
        s.setModel("swiftcode-cloud:swiftcode-1", for: .scCloud)
        let svc = service(s, overrides: [.scCloud: StubProvider(kind: .scCloud, text: "cloud-ok")])
        let resolved = try svc.resolve()
        #expect(resolved.kind == .scCloud)
        #expect(resolved.model == "swiftcode-cloud:swiftcode-1")
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.provider == .scCloud)
        #expect(completion.text == "cloud-ok")
    }

    @Test func resolvesCustomModelID() async throws {
        var s = settings(provider: .openRouter)
        s.customModelID = "meta-llama/llama-3-70b-instruct"
        let svc = service(s, overrides: [.openRouter: StubProvider(kind: .openRouter, text: "custom-ok")])
        let resolved = try svc.resolve()
        #expect(resolved.kind == .openRouter)
        #expect(resolved.model == "meta-llama/llama-3-70b-instruct")
    }

    @Test func providerDefaultWhenNothingStored() async throws {
        let svc = service(settings(provider: .openCode),
                          overrides: [.openCode: StubProvider(kind: .openCode, text: "default-ok")])
        let resolved = try svc.resolve()
        #expect(resolved.kind == .openCode)
        #expect(resolved.model == nil)
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.text == "default-ok")
    }

    @Test func collectsStreamedTextAndTruncation() async throws {
        let svc = service(settings(provider: .openRouter, model: "openai/gpt-4o-mini"),
                          overrides: [.openRouter: StubProvider(kind: .openRouter, text: "Hello", truncated: true)])
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.text == "Hello")
        #expect(completion.truncated)
    }

    @Test func freeOnlyBarsNonFreeModel() async throws {
        var s = settings(provider: .openRouter, model: "openai/gpt-4o")
        s.onlyUseFreeModels = true
        let svc = service(s, overrides: [.openRouter: StubProvider(kind: .openRouter, text: "x")])
        do {
            _ = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
            Issue.record("expected the free-only policy to refuse the model")
        } catch let error as LLMToolError {
            #expect(error == .ineligibleModel(model: "openai/gpt-4o", provider: .openRouter))
            #expect(error.localizedDescription.contains("free"))
        }
    }

    @Test func freeOnlyAllowsFreeModel() async throws {
        var s = settings(provider: .openRouter, model: "openai/gpt-4o-mini:free")
        s.onlyUseFreeModels = true
        let svc = service(s, overrides: [.openRouter: StubProvider(kind: .openRouter, text: "free-ok")])
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.text == "free-ok")
    }

    @Test func unconfiguredOpenRouterNamesTheKey() async throws {
        let svc = service(settings(provider: .openRouter))
        do {
            _ = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
            Issue.record("expected an unconfigured-provider failure")
        } catch let error as LLMToolError {
            guard case .providerUnavailable(let kind, let detail) = error else {
                Issue.record("expected providerUnavailable, got \(error)"); return
            }
            #expect(kind == .openRouter)
            #expect(detail.contains("API key"))
            #expect(error.localizedDescription.contains("no LLM provider is usable"))
        }
    }

    @Test func unconfiguredSCCloudNamesTheEndpoint() async throws {
        let svc = service(settings(provider: .scCloud))
        do {
            _ = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
            Issue.record("expected an unconfigured-cloud failure")
        } catch let error as LLMToolError {
            guard case .providerUnavailable(let kind, _) = error else {
                Issue.record("expected providerUnavailable, got \(error)"); return
            }
            #expect(kind == .scCloud)
            #expect(error.localizedDescription.contains("SwiftCode Cloud"))
        }
    }

    @Test func emptyResponseThrows() async throws {
        let svc = service(settings(provider: .openRouter, model: "openai/gpt-4o-mini"),
                          overrides: [.openRouter: StubProvider(kind: .openRouter, text: "")])
        do {
            _ = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
            Issue.record("expected an empty-response failure")
        } catch let error as LLMToolError {
            #expect(error == .emptyResponse(provider: .openRouter, model: "openai/gpt-4o-mini"))
        }
    }

    @Test func providerFailureIsMapped() async throws {
        let svc = service(settings(provider: .openRouter, model: "openai/gpt-4o-mini"),
                          overrides: [.openRouter: FailingProvider(kind: .openRouter, message: "boom")])
        do {
            _ = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
            Issue.record("expected a provider-failure mapping")
        } catch let error as LLMToolError {
            guard case .providerFailed(let kind, let detail) = error else {
                Issue.record("expected providerFailed, got \(error)"); return
            }
            #expect(kind == .openRouter)
            #expect(detail.contains("boom"))
        }
    }

    @Test func ollamaLoopbackEndToEnd() async throws {
        let server = try LoopbackServer { req in
            switch req.path {
            case "/api/tags":
                return .json(["models": [["name": "qwen2.5-coder:latest", "size": 1]]])
            case "/api/show":
                return .json(["model_info": ["general.architecture": "qwen2", "qwen2.context_length": 32768]])
            case "/api/chat":
                return .init(contentType: "application/x-ndjson", chunks: ndjson([
                    ["model": "m", "message": ["role": "assistant", "content": "Hel"], "done": false],
                    ["model": "m", "message": ["role": "assistant", "content": "lo"], "done": false],
                    ["model": "m", "message": ["role": "assistant", "content": ""], "done": true, "done_reason": "stop",
                     "prompt_eval_count": 12, "eval_count": 2],
                ]), delay: 0.02)
            default:
                return .text("", status: 404)
            }
        }
        var s = AssistantSettings()
        s.provider = .ollama
        s.ollamaURL = server.baseURL
        let svc = service(s)
        let completion = try await svc.complete(systemPrompt: "Be brief.", userText: "Hi")
        #expect(completion.text == "Hello")
        #expect(completion.provider == .ollama)
    }
}
