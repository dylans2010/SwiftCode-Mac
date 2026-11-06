import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeIDECore

// Wave 17, Slice A: the slash-command entry path — a Meta slash
// command typed at the composer is intercepted in
// `CodingAssistantModel.send` and its effect lands in the right
// place. No live `muse` binary, no real provider: a stub answers
// ordinary sends.

@MainActor
@Suite(.serialized) struct MetaSlashCommandHostTests {
    /// A scripted back end that answers every send with "ok".
    final class StubMetaProvider: AssistantProvider, @unchecked Sendable {
        let kind: ProviderKind = .metaAssist
        private let lock = NSLock()
        private(set) var requests: [ChatRequest] = []
        func availability() async -> ProviderAvailability { .ready([]) }
        func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
            lock.lock(); requests.append(request); lock.unlock()
            return AsyncThrowingStream { c in
                c.yield(.text("ok"))
                c.yield(.finished(nil))
                c.finish()
            }
        }
    }

    func makeModel() throws -> (CodingAssistantModel, StubMetaProvider, Preferences) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meta-slash-host-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "dev.swiftcode.test.meta-slash-\(UUID().uuidString)")!
        let prefs = Preferences(defaults: defaults)
        var settings = AssistantSettings()
        settings.provider = .metaAssist
        // A chosen model, so ordinary sends reach the back end
        // instead of failing for "no model available".
        settings.setModel("muse-wonder-1.0", for: .metaAssist)
        prefs.codingAssistant = settings
        let services = CodingAssistantServices()
        let stub = StubMetaProvider()
        // The stub answers for every provider: the non-Meta test
        // below needs a back end too, and nothing here may touch
        // the network.
        services.providerOverride = { _ in stub }
        let model = CodingAssistantModel(workspaceRoot: dir, archiveURL: nil, prefs: prefs, services: services)
        return (model, stub, prefs)
    }

    @Test func effortCommandUpdatesSettingsAndPostsResult() throws {
        let (model, _, prefs) = try makeModel()
        let id = model.send("/effort low")
        #expect(id != nil)
        #expect(prefs.codingAssistant.metaReasoningEffort == "low")
        let messages = model.conversation(id!)?.messages ?? []
        #expect(messages.count == 2)
        #expect(messages[0].role == .user && messages[0].text == "/effort low")
        #expect(messages[1].role == .assistant && messages[1].text == "Meta reasoning effort set to 'low'.")
        #expect(messages[1].isComplete)
    }

    @Test func modelCommandRecordsVerbatimAndIsUsedAsIs() throws {
        let (model, _, prefs) = try makeModel()
        // No availability at all: the stored choice must still
        // be the turn's model, never the first discovered one.
        let id = model.send("/model muse-swift-2.0")
        #expect(id != nil)
        #expect(prefs.codingAssistant.model(for: .metaAssist) == "muse-swift-2.0")
        #expect(model.modelID == "muse-swift-2.0")
        let messages = model.conversation(id!)?.messages ?? []
        #expect(messages.last?.text.contains("not in the known Meta catalog") == true)
    }

    @Test func clearCommandStartsAFreshConversation() async throws {
        let (model, _, _) = try makeModel()
        let first = model.send("hello")!
        await model.response(first)?.value
        #expect(model.conversation(first)?.messages.count == 2)
        let cleared = model.send("/clear")
        #expect(cleared != nil && cleared != first)
        #expect(model.conversation(cleared!)?.messages.last?.text == "Cleared Assist session.")
        // The old conversation stays in the library — SwiftCode never
        // deletes a transcript implicitly.
        #expect(model.conversation(first)?.messages.count == 2)
    }

    @Test func loginCommandSurfacesTheInstruction() throws {
        let (model, _, _) = try makeModel()
        let id = model.send("/login")
        #expect(id != nil)
        let messages = model.conversation(id!)?.messages ?? []
        #expect(messages.last?.text.contains("run `muse` once in Terminal") == true)
    }

    @Test func commandWithoutArgumentStaysInTheInput() throws {
        let (model, stub, _) = try makeModel()
        #expect(model.send("/effort") == nil)
        #expect(model.conversations.isEmpty)
        #expect(stub.requests.isEmpty)
    }

    @Test func unknownSlashTextIsSentNormally() async throws {
        let (model, stub, _) = try makeModel()
        let id = model.send("/usr/bin/ls")!
        await model.response(id)?.value
        #expect(stub.requests.count == 1)
        #expect(stub.requests[0].messages.last?.content == "/usr/bin/ls")
    }

    @Test func slashCommandsAreMetaOnly() async throws {
        let (model, stub, prefs) = try makeModel()
        var settings = prefs.codingAssistant
        settings.provider = .ollama
        // A chosen model, so the send reaches the back end
        // instead of failing for "no model available".
        settings.setModel("qwen2.5-coder", for: .ollama)
        prefs.codingAssistant = settings
        let id = model.send("/clear")!
        await model.response(id)?.value
        // Not intercepted: the text went to the (stub) provider.
        #expect(stub.requests.count == 1)
        #expect(stub.requests[0].messages.last?.content == "/clear")
    }
}
