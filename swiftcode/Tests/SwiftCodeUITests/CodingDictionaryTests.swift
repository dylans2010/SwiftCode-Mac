import XCTest
@testable import SwiftCodeUI
import SwiftCodeAssistant

// NOTE: No Swift toolchain exists in this environment, so these tests
// have NOT been compiled or run — statically verified only. On Dylan's
// Mac: run with `swift test --filter CodingDictionaryTests`.
//
// Wave 17, Slice C: tests for the Coding Dictionary
// (`CodingDictionaryService` + models + entry rendering). The
// provider is always a fake — no network, no host provider, no key
// is ever involved. History tests use a throwaway UserDefaults
// suite, removed in tearDown.

@MainActor
final class CodingDictionaryTests: XCTestCase {

    // MARK: - Fake provider

    private final class FakeProvider: AssistantProvider, @unchecked Sendable {
        let kind: ProviderKind
        var availabilityResult: ProviderAvailability
        var scriptedText: String?
        var failure: (any Error)?
        var requests: [ChatRequest] = []

        init(
            kind: ProviderKind = .ollama,
            availability: ProviderAvailability = .ready([]),
            scriptedText: String? = nil,
            failure: (any Error)? = nil
        ) {
            self.kind = kind
            self.availabilityResult = availability
            self.scriptedText = scriptedText
            self.failure = failure
        }

        func availability() async -> ProviderAvailability { availabilityResult }

        func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
            requests.append(request)
            if let failure {
                return AsyncThrowingStream { $0.finish(throwing: failure) }
            }
            let text = scriptedText ?? ""
            return AsyncThrowingStream { continuation in
                if !text.isEmpty { continuation.yield(.text(text)) }
                continuation.yield(.finished(nil))
                continuation.finish()
            }
        }
    }

    // MARK: - Fixtures

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.swiftcode.test.dictionary-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeService(
        provider: FakeProvider,
        modelID: String? = "test-model"
    ) -> CodingDictionaryService {
        CodingDictionaryService(userDefaults: defaults) {
            (provider as any AssistantProvider, modelID)
        }
    }

    private static let entryJSON = """
        {
          "version": "1.0",
          "confidence": 95,
          "query": "TaskGroup",
          "title": "TaskGroup",
          "subtitle": "A group that collects concurrent child tasks",
          "kind": "Struct",
          "category": "Language",
          "difficulty": "Intermediate",
          "overview": "TaskGroup collects child tasks.",
          "definition": "A task group.",
          "summary": "Use it for fan-out.",
          "syntax": "withTaskGroup(of: Int.self) { group in }",
          "parameters": [{ "name": "of", "type": "T.Type", "description": "The result type" }],
          "returnValue": { "type": "Int", "description": "The collected total" },
          "examples": [{ "title": "Fan-out", "code": "let total = await withTaskGroup(of: Int.self) { _ in 1 }" }],
          "commonMistakes": [{ "description": "Forgetting addTask", "explanation": "No work runs", "fix": "Call addTask" }],
          "bestPractices": ["Cancel when done"],
          "performanceNotes": "Cheap.",
          "threadSafety": "Sendable.",
          "securityNotes": "",
          "availability": ["macOS 13.0+"],
          "relatedConcepts": ["async let"],
          "aliases": [],
          "keywords": ["concurrency"],
          "warnings": [],
          "notes": [],
          "seeAlso": ["Task"],
          "references": [],
          "appleDocsSummary": "",
          "swiftVersion": "Swift 5.5+",
          "alternativeAPIs": ["async let"],
          "codeSnippet": "withTaskGroup(of: Int.self) { _ in 1 }",
          "complexity": "O(n)",
          "memoryConsiderations": ""
        }
        """

    // MARK: - Models

    func testSparseEntryDecodesWithDefaults() throws {
        let data = #"{"query": "Foo", "title": "Foo", "definition": "A thing."}"#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(CodingDictionaryResult.self, from: data)
        XCTAssertEqual(entry.query, "Foo")
        XCTAssertEqual(entry.definition, "A thing.")
        XCTAssertEqual(entry.confidence, 100)
        XCTAssertEqual(entry.version, "1.0")
        XCTAssertTrue(entry.parameters.isEmpty)
        XCTAssertTrue(entry.examples.isEmpty)
        XCTAssertEqual(entry.returnValue.type, "")
    }

    func testFullEntryDecodes() throws {
        let entry = try JSONDecoder().decode(CodingDictionaryResult.self, from: Self.entryJSON.data(using: .utf8)!)
        XCTAssertEqual(entry.title, "TaskGroup")
        XCTAssertEqual(entry.confidence, 95)
        XCTAssertEqual(entry.parameters, [DictionaryParameter(name: "of", type: "T.Type", description: "The result type")])
        XCTAssertEqual(entry.examples, [DictionaryExample(title: "Fan-out", code: "let total = await withTaskGroup(of: Int.self) { _ in 1 }")])
        XCTAssertEqual(entry.commonMistakes.count, 1)
        XCTAssertEqual(entry.bestPractices, ["Cancel when done"])
        XCTAssertEqual(entry.complexity, "O(n)")
    }

    // MARK: - Prompt and extraction

    func testSystemPromptContainsQueryAndSchema() {
        let prompt = CodingDictionaryService.systemPrompt(for: "TaskGroup")
        XCTAssertTrue(prompt.contains("SwiftCode Coding Dictionary"))
        XCTAssertTrue(prompt.contains("\"query\": \"TaskGroup\""))
        XCTAssertTrue(prompt.contains("\"parameters\""))
        XCTAssertTrue(prompt.contains("ONLY valid, raw JSON"))
        XCTAssertFalse(prompt.contains("SwiftCode"))
    }

    func testExtractJSONFindsFencedJSON() throws {
        let fenced = "Here is your entry:\n```json\n\(Self.entryJSON)\n```\nHope that helps."
        let extracted = CodingDictionaryService.extractJSON(from: fenced)
        XCTAssertNotNil(extracted)
        let entry = try JSONDecoder().decode(CodingDictionaryResult.self, from: extracted!.data(using: .utf8)!)
        XCTAssertEqual(entry.title, "TaskGroup")
    }

    func testExtractJSONReturnsNilWithoutBraces() {
        XCTAssertNil(CodingDictionaryService.extractJSON(from: "no json here"))
        XCTAssertNil(CodingDictionaryService.extractJSON(from: ""))
    }

    // MARK: - History

    func testHistoryAddPinDeleteClear() {
        let service = CodingDictionaryService(userDefaults: defaults)
        service.addToHistory(query: "TaskGroup")
        service.addToHistory(query: "Actor")
        XCTAssertEqual(service.history.map(\.query), ["Actor", "TaskGroup"])
        // Re-adding moves nothing and duplicates nothing.
        service.addToHistory(query: "TaskGroup")
        XCTAssertEqual(service.history.map(\.query), ["Actor", "TaskGroup"])
        let actorID = service.history[0].id
        service.togglePin(id: actorID)
        XCTAssertEqual(service.history.map(\.query), ["Actor", "TaskGroup"])
        XCTAssertTrue(service.history[0].isPinned)
        service.deleteHistoryItem(id: actorID)
        XCTAssertEqual(service.history.map(\.query), ["TaskGroup"])
        service.clearHistory()
        XCTAssertTrue(service.history.isEmpty)
    }

    func testHistoryPersistsAcrossServiceInstances() {
        let first = CodingDictionaryService(userDefaults: defaults)
        first.addToHistory(query: "TaskGroup")
        let second = CodingDictionaryService(userDefaults: defaults)
        XCTAssertEqual(second.history.map(\.query), ["TaskGroup"])
    }

    // MARK: - Lookup through a fake provider

    func testDefineReturnsDecodedEntry() async throws {
        let provider = FakeProvider(scriptedText: Self.entryJSON)
        let service = makeService(provider: provider)
        let entry = try await service.define(query: "TaskGroup")
        XCTAssertEqual(entry.title, "TaskGroup")
        XCTAssertEqual(entry.query, "TaskGroup")
        XCTAssertEqual(provider.requests.count, 1)
        let request = try XCTUnwrap(provider.requests.first)
        XCTAssertNil(request.workingDirectory, "A definition lookup must not run tools anywhere")
        XCTAssertEqual(request.model, "test-model")
        XCTAssertTrue(request.instructions.contains("SwiftCode Coding Dictionary"))
        XCTAssertEqual(request.messages, [ChatMessage(.user, "User Query: TaskGroup")])
    }

    func testDefineRefusesAgentProvider() async {
        let provider = FakeProvider(kind: .claudeCode)
        let service = makeService(provider: provider)
        do {
            _ = try await service.define(query: "TaskGroup")
            XCTFail("Expected .agentProvider")
        } catch let error as CodingDictionaryError {
            XCTAssertEqual(error, .agentProvider(.claudeCode))
        } catch {
            XCTFail("Expected CodingDictionaryError, got \(error)")
        }
        XCTAssertTrue(provider.requests.isEmpty, "An agent provider must never receive the request")
    }

    func testDefineThrowsWhenProviderNotReady() async {
        let provider = FakeProvider(availability: .notRunning(hint: "Ollama is not running."))
        let service = makeService(provider: provider)
        do {
            _ = try await service.define(query: "TaskGroup")
            XCTFail("Expected .providerNotReady")
        } catch let error as CodingDictionaryError {
            XCTAssertEqual(error, .providerNotReady("Ollama is not running."))
        } catch {
            XCTFail("Expected CodingDictionaryError, got \(error)")
        }
    }

    func testDefineThrowsOnInvalidJSON() async {
        let provider = FakeProvider(scriptedText: "This is prose, not JSON.")
        let service = makeService(provider: provider)
        do {
            _ = try await service.define(query: "TaskGroup")
            XCTFail("Expected .invalidJSON")
        } catch let error as CodingDictionaryError {
            XCTAssertEqual(error, .invalidJSON("This is prose, not JSON."))
        } catch {
            XCTFail("Expected CodingDictionaryError, got \(error)")
        }
    }

    func testDefineThrowsOnEmptyResponse() async {
        let provider = FakeProvider(scriptedText: "")
        let service = makeService(provider: provider)
        do {
            _ = try await service.define(query: "TaskGroup")
            XCTFail("Expected .emptyResponse")
        } catch let error as CodingDictionaryError {
            XCTAssertEqual(error, .emptyResponse)
        } catch {
            XCTFail("Expected CodingDictionaryError, got \(error)")
        }
    }

    func testDefineThrowsOnEmptyQuery() async {
        let provider = FakeProvider(scriptedText: Self.entryJSON)
        let service = makeService(provider: provider)
        do {
            _ = try await service.define(query: "   ")
            XCTFail("Expected .emptyResponse")
        } catch let error as CodingDictionaryError {
            XCTAssertEqual(error, .emptyResponse)
        } catch {
            XCTFail("Expected CodingDictionaryError, got \(error)")
        }
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testDefineMapsProviderFailure() async {
        let failure = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let provider = FakeProvider(failure: failure)
        let service = makeService(provider: provider)
        do {
            _ = try await service.define(query: "TaskGroup")
            XCTFail("Expected .providerFailure")
        } catch let error as CodingDictionaryError {
            XCTAssertEqual(error, .providerFailure("boom"))
        } catch {
            XCTFail("Expected CodingDictionaryError, got \(error)")
        }
    }

    // MARK: - Rendering

    func testEntryTextRendersAllSections() throws {
        let entry = try JSONDecoder().decode(CodingDictionaryResult.self, from: Self.entryJSON.data(using: .utf8)!)
        let text = CodingDictionaryEntryText.attributedString(for: entry).string
        for fragment in ["TaskGroup", "A task group.", "withTaskGroup(of: Int.self)",
                         "Fan-out", "Forgetting addTask", "Cancel when done",
                         "O(n)", "async let"] {
            XCTAssertTrue(text.contains(fragment), "Expected “\(fragment)” in rendered entry")
        }
    }
}
