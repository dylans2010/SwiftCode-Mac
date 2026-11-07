import XCTest
@testable import SwiftCodeSDK
import SwiftCodeAssistant

final class SDKAssistHostBackendTests: XCTestCase {

    private final class FakeAssistantProvider: AssistantProvider, @unchecked Sendable {
        let kind: ProviderKind
        var availabilityResult: ProviderAvailability = .ready([ModelInfo(id: "fake-model")])
        var scriptedEvents: [ChatEvent] = []
        var sendError: (any Error)?
        private(set) var receivedRequests: [ChatRequest] = []

        init(kind: ProviderKind, scriptedEvents: [ChatEvent] = [], sendError: (any Error)? = nil) {
            self.kind = kind
            self.scriptedEvents = scriptedEvents
            self.sendError = sendError
        }

        func availability() async -> ProviderAvailability { availabilityResult }

        func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
            receivedRequests.append(request)
            let events = scriptedEvents
            let error = sendError
            return AsyncThrowingStream { continuation in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    private final class EchoAssistantProvider: AssistantProvider, @unchecked Sendable {
        let kind: ProviderKind = .ollama

        func availability() async -> ProviderAvailability { .ready([ModelInfo(id: "fake-model")]) }

        func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
            let last = request.messages.last?.content ?? ""
            return AsyncThrowingStream { continuation in
                continuation.yield(.text("echo:" + last))
                continuation.yield(.finished(nil))
                continuation.finish()
            }
        }
    }

    private struct FakeResolver: SDKAssistProviderResolving {
        let provider: any AssistantProvider
        let modelID: String?

        func resolveProvider(for session: SDKAssistSession) async throws -> SDKAssistProviderResolution {
            SDKAssistProviderResolution(provider: provider, modelID: modelID)
        }
    }

    private func makeSession(
        extensionID: String = "com.example.test",
        systemPrompt: String? = "Be brief.",
        messages: [SDKAssistMessage] = [],
        isClosed: Bool = false
    ) -> SDKAssistSession {
        SDKAssistSession(
            extensionID: extensionID,
            systemPrompt: systemPrompt,
            isClosed: isClosed,
            messages: messages,
            allowedToolIDs: ["test.tool"]
        )
    }

    private func assertThrowsServiceUnavailable(
        _ work: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await work()
            XCTFail("Expected .serviceUnavailable", file: file, line: line)
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .serviceUnavailable, file: file, line: line)
        } catch {
            XCTFail("Expected SDKError, got \(error)", file: file, line: line)
        }
    }

    func testCompleteSendsOnlyTheExtensionSession() async throws {
        let provider = FakeAssistantProvider(
            kind: .ollama,
            scriptedEvents: [.text("done"), .finished(nil)]
        )
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: "fake-model"))
        let session = makeSession(messages: [
            SDKAssistMessage(role: .user, content: "first question"),
            SDKAssistMessage(role: .assistant, content: "first answer"),
        ])
        let text = try await backend.complete(session: session, message: "second question")
        XCTAssertEqual(text, "done")
        XCTAssertEqual(provider.receivedRequests.count, 1)
        let request = provider.receivedRequests[0]
        XCTAssertEqual(request.instructions, "Be brief.")
        XCTAssertEqual(request.messages.map(\.content), ["first question", "first answer", "second question"])
        XCTAssertEqual(request.messages.map(\.role), [.user, .assistant, .user])
        XCTAssertNil(request.workingDirectory)
        XCTAssertEqual(request.model, "fake-model")
    }

    func testCompleteUsesDefaultInstructionsWithoutSystemPrompt() async throws {
        let provider = FakeAssistantProvider(kind: .openAI, scriptedEvents: [.text("ok"), .finished(nil)])
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: nil))
        let session = makeSession(systemPrompt: nil)
        _ = try await backend.complete(session: session, message: "hi")
        XCTAssertEqual(provider.receivedRequests.count, 1)
        XCTAssertEqual(provider.receivedRequests[0].instructions, SDKAssistHostBackend.defaultInstructions)
        XCTAssertNil(provider.receivedRequests[0].model)
    }

    func testCallerACannotSeeCallerBResults() async throws {
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: EchoAssistantProvider(), modelID: nil))
        let sessionA = makeSession(extensionID: "com.example.alpha")
        let sessionB = makeSession(extensionID: "com.example.beta")
        let textA = try await backend.complete(session: sessionA, message: "alpha-marker")
        let textB = try await backend.complete(session: sessionB, message: "beta-marker")
        XCTAssertEqual(textA, "echo:alpha-marker")
        XCTAssertEqual(textB, "echo:beta-marker")
        XCTAssertFalse(textA.contains("beta"))
        XCTAssertFalse(textB.contains("alpha"))
    }

    func testStreamDropsHostActivityAndEndsWithEmptyDelta() async throws {
        let provider = FakeAssistantProvider(
            kind: .openAI,
            scriptedEvents: [
                .text("Hel"),
                .activity("Reading /Users/user/host.swift"),
                .text("lo"),
                .truncated,
                .finished(nil),
            ]
        )
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: nil))
        var deltas: [String] = []
        for try await delta in await backend.stream(session: makeSession(), message: "hi") {
            deltas.append(delta)
        }
        XCTAssertEqual(deltas, ["Hel", "lo", ""])
        XCTAssertFalse(deltas.joined().contains("Reading"))
    }

    func testStreamWithoutResolverFails() async throws {
        let backend = SDKAssistHostBackend(resolver: nil)
        var events: [SDKAssistStreamEvent] = []
        do {
            for try await delta in await backend.stream(session: makeSession(), message: "hi") {
                events.append(.delta(delta))
            }
            XCTFail("Expected the stream to throw")
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .serviceUnavailable)
        }
        XCTAssertTrue(events.isEmpty)
    }

    func testProviderKindPartitionCoversAllCases() {
        let allowed = SDKAssistHostBackend.textCompletionProviderKinds
        let rejected = SDKAssistHostBackend.agentProviderKinds
        XCTAssertTrue(allowed.isDisjoint(with: rejected))
        XCTAssertEqual(allowed.union(rejected), Set(ProviderKind.allCases))
    }

    func testAgentProviderKindsAreRefused() async {
        for kind in SDKAssistHostBackend.agentProviderKinds {
            let provider = FakeAssistantProvider(kind: kind, scriptedEvents: [.text("must not serve"), .finished(nil)])
            let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: nil))
            await assertThrowsServiceUnavailable {
                _ = try await backend.complete(session: self.makeSession(), message: "hi")
            }
            XCTAssertTrue(provider.receivedRequests.isEmpty, "Agent provider \(kind) must never receive a request")
        }
    }

    func testNoResolverThrowsServiceUnavailable() async {
        let backend = SDKAssistHostBackend(resolver: nil)
        await assertThrowsServiceUnavailable {
            _ = try await backend.complete(session: self.makeSession(), message: "hi")
        }
    }

    func testProviderNotReadyThrowsServiceUnavailable() async {
        let provider = FakeAssistantProvider(kind: .ollama, scriptedEvents: [.text("must not serve"), .finished(nil)])
        provider.availabilityResult = .notRunning(hint: "Ollama is not running.")
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: nil))
        await assertThrowsServiceUnavailable {
            _ = try await backend.complete(session: self.makeSession(), message: "hi")
        }
        XCTAssertTrue(provider.receivedRequests.isEmpty)
    }

    func testClosedSessionThrowsInvalidArgument() async {
        let provider = FakeAssistantProvider(kind: .ollama, scriptedEvents: [.text("must not serve"), .finished(nil)])
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: nil))
        let closed = makeSession(isClosed: true)
        do {
            _ = try await backend.complete(session: closed, message: "hi")
            XCTFail("Expected .invalidArgument for a closed session")
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .invalidArgument)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(provider.receivedRequests.isEmpty)
    }

    func testProviderErrorsAreNotForwardedVerbatim() async throws {
        let provider = FakeAssistantProvider(kind: .ollama, sendError: AssistantError.failed("boom-marker"))
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: nil))
        do {
            _ = try await backend.complete(session: makeSession(), message: "hi")
            XCTFail("Expected the provider failure to surface as .serviceUnavailable")
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .serviceUnavailable)
            XCTAssertFalse(error.message.contains("boom-marker"))
            XCTAssertFalse(error.suggestion?.contains("boom-marker") ?? false)
        }
    }

    func testExecuteToolIsNotAttached() async {
        let provider = FakeAssistantProvider(kind: .ollama, scriptedEvents: [.text("must not serve"), .finished(nil)])
        let backend = SDKAssistHostBackend(resolver: FakeResolver(provider: provider, modelID: nil))
        let call = SDKAssistToolCall(toolName: "test.tool", arguments: [:])
        do {
            _ = try await backend.executeTool(session: makeSession(), call: call)
            XCTFail("Expected executeTool to throw .serviceUnavailable")
        } catch let error as SDKError {
            XCTAssertEqual(error.code, .serviceUnavailable)
            XCTAssertTrue(error.suggestion?.contains("not attached") ?? false)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(provider.receivedRequests.isEmpty)
    }
}
