//
//  SystemIndexTestSuite.swift
//  SwiftCode
//
//  Targeted tests for SystemIndex (instruction indexing/retrieval), the
//  Markdown rendering repair, and the unified request-phase state model.
//
//  Follows the same pattern as AssistRuntimeTestSuite: runAllTests() returns
//  [RuntimeTestCaseResult] for aggregation by AssistRuntimeTestSuite.
//

import Foundation
import os

@MainActor
public final class SystemIndexTestSuite: Sendable {
    public static let shared = SystemIndexTestSuite()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "SystemIndexTestSuite")

    private init() {}

    public func runAllTests() async -> [RuntimeTestCaseResult] {
        var results: [RuntimeTestCaseResult] = []
        results.append(testDocumentParsing())
        results.append(testChunking())
        results.append(testCategoryClassification())
        results.append(testRankingPrefersRelevantDocument())
        results.append(testLedgerPreventsReinjection())
        results.append(await testSafeguardsSurviveTinyBudget())
        results.append(await testBundleDiscoveryAndRetrieval())
        results.append(await testNoResultVsIndexFailure())
        results.append(testMarkdownInlineSourcePreserved())
        results.append(testMarkdownNestedLists())
        results.append(testMarkdownStreamingFenceBalancing())
        results.append(testRequestPhaseTerminalStates())
        results.append(testRuntimeInstructionsPreservesBaseline())
        results.append(testRuntimeInstructionsGreetingFastPath())
        results.append(testTimeoutErrorLocalizedDescription())
        results.append(testRequestGenerationEquality())
        results.append(testQueuedMessagePreservesEnvelope())
        return results
    }

    private func result(testName: String, passed: Bool, message: String, start: Date) -> RuntimeTestCaseResult {
        RuntimeTestCaseResult(testName: testName, passed: passed, message: message,
                              duration: Date().timeIntervalSince(start))
    }

    // MARK: - Parsing

    func testDocumentParsing() -> RuntimeTestCaseResult {
        let start = Date()
        let text = """
        <!-- system-index-depends: Safeguards.md, CallTool.md -->
        # CallTool — Procedures

        Intro paragraph.

        ## 1. Selection

        Do the thing.

        ## 2. Validation

        Check params.
        """
        let doc = SystemIndexService.parseDocument(relativePath: "CallTool.md", text: text)
        let checks = [
            doc.title == "CallTool — Procedures",
            doc.dependencies == ["Safeguards.md", "CallTool.md"],
            doc.sections.contains(where: { $0.heading == "1. Selection" && $0.text.contains("Do the thing.") }),
            doc.sections.contains(where: { $0.heading == "2. Validation" }),
            !doc.contentHash.isEmpty,
            doc.sections.allSatisfy { !$0.id.isEmpty && $0.tokenEstimate > 0 },
        ]
        let passed = checks.allSatisfy { $0 }
        return result(testName: "SystemIndex: Document Parsing", passed: passed,
                      message: passed ? "Title, dependencies, sections, hashes parsed (\(doc.sections.count) sections)."
                                      : "Parsing checks failed: \(checks).", start: start)
    }

    func testChunking() -> RuntimeTestCaseResult {
        let start = Date()
        let paragraph = String(repeating: "Lorem ipsum dolor sit amet. ", count: 8) // ~200 chars
        let text = (0..<60).map { "Paragraph \($0).\n\n\(paragraph)" }.joined(separator: "\n\n")
        let chunks = SystemIndexService.chunkText(text, maxChars: 3000)
        let sizesOK = chunks.allSatisfy { $0.count <= 3400 }
        let overlapOK: Bool = {
            guard chunks.count >= 2 else { return false }
            let paras = { (c: String) in c.components(separatedBy: "\n\n") }
            return paras(chunks[0]).last == paras(chunks[1]).first
        }()
        let passed = chunks.count >= 3 && sizesOK && overlapOK
            && chunks[0].hasPrefix("Paragraph 0.")
        return result(testName: "SystemIndex: Chunking", passed: passed,
                      message: passed ? "\(chunks.count) paragraph-aligned chunks with overlap."
                                      : "Chunking failed (count=\(chunks.count), sizesOK=\(sizesOK), overlapOK=\(overlapOK)).",
                      start: start)
    }

    // MARK: - Classification & ranking

    func testCategoryClassification() -> RuntimeTestCaseResult {
        let start = Date()
        let cases: [(String, InstructionQueryContext.TaskCategory)] = [
            ("write a file and delete the temp directory", .fileOperations),
            ("sign in with google, my oauth token expired", .authentication),
            ("build the app and run the test suite", .buildAndTest),
            ("hello there", .general),
        ]
        let failures = cases.filter { SystemIndexService.classifyCategory(for: $0.0) != $0.1 }
        let passed = failures.isEmpty
        return result(testName: "SystemIndex: Task Classification", passed: passed,
                      message: passed ? "All \(cases.count) classifications correct."
                                      : "Misclassified: \(failures.map(\.0)).", start: start)
    }

    func testRankingPrefersRelevantDocument() -> RuntimeTestCaseResult {
        let start = Date()
        let fileDoc = SystemIndexService.parseDocument(relativePath: "FileOperations.md", text: """
        # FileOperations — Files

        ## Deleting files

        To delete a file, use the file_delete tool. Deletion is destructive and cannot be undone.
        """)
        let streamDoc = SystemIndexService.parseDocument(relativePath: "Streaming.md", text: """
        # Streaming — Output

        ## Partial deltas

        Stream partial output deltas to the user interface incrementally.
        """)
        let query = InstructionQueryContext(userText: "how do I delete a file permanently",
                                            taskCategory: .fileOperations, maxTokens: 4000)
        let terms = SystemIndexService.queryTerms(for: query)
        let weights = SystemIndexRankingWeights()
        let fileScore = fileDoc.sections.map {
            SystemIndexService.score(section: $0, queryTerms: terms, isBaseline: false, weights: weights).0
        }.max() ?? 0
        let streamScore = streamDoc.sections.map {
            SystemIndexService.score(section: $0, queryTerms: terms, isBaseline: false, weights: weights).0
        }.max() ?? 0
        let passed = fileScore > streamScore && fileScore > 0
        return result(testName: "SystemIndex: Ranking Relevance", passed: passed,
                      message: passed ? "FileOperations (\(String(format: "%.2f", fileScore))) outranked Streaming (\(String(format: "%.2f", streamScore)))."
                                      : "Ranking failed: file=\(fileScore), stream=\(streamScore).", start: start)
    }

    func testLedgerPreventsReinjection() -> RuntimeTestCaseResult {
        let start = Date()
        var ledger = SystemIndexRequestLedger()
        let fake = SystemIndexBudgetResult(
            retrievals: [
                SystemIndexRetrieval(sectionID: "a#x-0", documentPath: "A.md", documentTitle: "A",
                                     sectionHeading: "X", text: "hello", score: 1, reason: .keywordMatch, contentHash: "h"),
                SystemIndexRetrieval(sectionID: "b#y-0", documentPath: "B.md", documentTitle: "B",
                                     sectionHeading: "Y", text: "world", score: 1, reason: .keywordMatch, contentHash: "h"),
            ],
            totalTokenEstimate: 10, omittedSectionCount: 0, safeguardsIncluded: false,
            budgetExceeded: false, notes: []
        )
        ledger.record(fake)
        let passed = ledger.retrievedChunkIDs == ["a#x-0", "b#y-0"] && ledger.retrievalRounds == 1
        ledger.reset()
        let resetOK = ledger.retrievedChunkIDs.isEmpty && ledger.retrievalRounds == 0
        return result(testName: "SystemIndex: Request Ledger", passed: passed && resetOK,
                      message: (passed && resetOK) ? "Ledger records and resets chunk IDs."
                                                   : "Ledger bookkeeping failed.", start: start)
    }

    // MARK: - Live index (bundled System Assets)

    func testSafeguardsSurviveTinyBudget() async -> RuntimeTestCaseResult {
        let start = Date()
        await SystemIndexService.shared.ensureReady()
        let query = InstructionQueryContext(userText: "tell me a joke", taskCategory: .general, maxTokens: 50)
        let res = await SystemIndexService.shared.retrieve(for: query)
        // Mandatory safeguards are never silently dropped for budget reasons.
        let passed = res.safeguardsIncluded && res.budgetExceeded
        return result(testName: "SystemIndex: Safeguards Survive Budget", passed: passed,
                      message: passed ? "Safeguards preserved under a 50-token budget (exceeded flag set)."
                                      : "safeguardsIncluded=\(res.safeguardsIncluded), budgetExceeded=\(res.budgetExceeded).",
                      start: start)
    }

    func testBundleDiscoveryAndRetrieval() async -> RuntimeTestCaseResult {
        let start = Date()
        await SystemIndexService.shared.ensureReady()
        let status = await SystemIndexService.shared.status()
        guard case .ready(let docs, let chunks) = status, docs >= 20 else {
            return result(testName: "SystemIndex: Bundle Discovery", passed: false,
                          message: "Index not ready: \(status).", start: start)
        }
        let query = InstructionQueryContext(userText: "how do I safely delete a file in the workspace",
                                            taskCategory: .fileOperations, maxTokens: 4000)
        let res = await SystemIndexService.shared.retrieve(for: query)
        let paths = Set(res.retrievals.map(\.documentPath))
        let passed = paths.contains("FileOperations.md") || paths.contains("Safeguards.md")
        return result(testName: "SystemIndex: Bundle Discovery", passed: passed,
                      message: passed ? "\(docs) docs / \(chunks) chunks; file-deletion query retrieved: \(paths.sorted().prefix(4).joined(separator: ", "))."
                                      : "Retrieval missed FileOperations/Safeguards: \(paths.sorted()).",
                      start: start)
    }

    func testNoResultVsIndexFailure() async -> RuntimeTestCaseResult {
        let start = Date()
        await SystemIndexService.shared.ensureReady()
        // A nonsense query against a healthy index yields low/empty results —
        // which must differ from an index failure (explicit notes).
        let query = InstructionQueryContext(userText: "zxqv wjbx kplm qwertyuiop",
                                            taskCategory: .general, maxTokens: 4000)
        let res = await SystemIndexService.shared.retrieve(for: query)
        let status = await SystemIndexService.shared.status()
        let indexHealthy: Bool
        if case .ready = status { indexHealthy = true } else { indexHealthy = false }
        // Healthy index + nonsense query: only baseline sections (score 0+boost), no failure notes.
        let failureNotes = res.notes.filter { $0.contains("unavailable") || $0.contains("failed") }
        let passed = indexHealthy && failureNotes.isEmpty
        return result(testName: "SystemIndex: No-Result vs Failure", passed: passed,
                      message: passed ? "Nonsense query returned \(res.retrievals.count) baseline section(s), no failure notes."
                                      : "notes=\(res.notes).", start: start)
    }

    // MARK: - Markdown rendering

    func testMarkdownInlineSourcePreserved() -> RuntimeTestCaseResult {
        let start = Date()
        let blocks = MarkdownParser.shared.parse("Hello **bold** and *italic* with `code` and [link](https://example.com) plus ~~strike~~.")
        guard case .paragraph(let text)? = blocks.first else {
            return result(testName: "Markdown: Inline Formatting", passed: false,
                          message: "No paragraph block parsed.", start: start)
        }
        let expected = ["**bold**", "*italic*", "`code`", "[link](https://example.com)", "~~strike~~"]
        let missing = expected.filter { !text.contains($0) }
        let passed = missing.isEmpty
        return result(testName: "Markdown: Inline Formatting", passed: passed,
                      message: passed ? "Inline source preserved: \(text)."
                                      : "Stripped markers: \(missing). Got: \(text)", start: start)
    }

    func testMarkdownNestedLists() -> RuntimeTestCaseResult {
        let start = Date()
        let blocks = MarkdownParser.shared.parse("- alpha\n  - alpha-one\n  - alpha-two\n- beta")
        guard case .bulletList(let items)? = blocks.first else {
            return result(testName: "Markdown: Nested Lists", passed: false,
                          message: "No bullet list parsed: \(blocks.map(\.id)).", start: start)
        }
        let passed = items.count == 2
            && items[0].text == "alpha"
            && items[0].children.map(\.text) == ["alpha-one", "alpha-two"]
            && items[1].text == "beta"
        return result(testName: "Markdown: Nested Lists", passed: passed,
                      message: passed ? "Nested items preserved under parent."
                                      : "Got: \(items.map { "\($0.text)->\($0.children.map(\.text))" }).", start: start)
    }

    func testMarkdownStreamingFenceBalancing() -> RuntimeTestCaseResult {
        let start = Date()
        // Partial stream: unclosed fence must still parse as a code block.
        let blocks = MarkdownParser.shared.parse("Here is code:\n```swift\nlet x = 1")
        let hasCode = blocks.contains {
            if case .codeBlock = $0 { return true }
            return false
        }
        let hasIntro = blocks.contains {
            if case .paragraph(let t) = $0 { return t.contains("Here is code") }
            return false
        }
        let passed = hasCode && hasIntro
        return result(testName: "Markdown: Streaming Fences", passed: passed,
                      message: passed ? "Unclosed fence parsed as code block."
                                      : "Blocks: \(blocks.map(\.id)).", start: start)
    }

    // MARK: - Request phase model

    func testRequestPhaseTerminalStates() -> RuntimeTestCaseResult {
        let start = Date()
        let terminal: [AssistRequestPhase] = [.completed, .failed, .cancelled, .timedOut]
        let nonTerminal: [AssistRequestPhase] = [.idle, .preparingRequest, .retrievingInstructions,
                                                .waitingForModel, .receivingResponse, .executingTool]
        let passed = terminal.allSatisfy(\.isTerminal)
            && !nonTerminal.contains(where: \.isTerminal)
            && AssistRequestPhase.waitingForModel.statusText == "Waiting for model output…"
            && AssistRequestPhase.preparingRequest.statusText == "Preparing request…"
            && AssistRequestPhase.retrievingInstructions.statusText == "Loading instructions…"
        return result(testName: "Request Phase: Terminal States", passed: passed,
                      message: passed ? "Terminal phases and status texts correct."
                                      : "Phase model mismatch.", start: start)
    }

    // MARK: - Session instruction assembly (canonical baseline)

    /// The new canonical baseline (routing index + Identity + Safeguards)
    /// must be carried into SDK sessions in full — Identity and Safeguards
    /// are mandatory and must never be stripped by section extraction.
    func testRuntimeInstructionsPreservesBaseline() -> RuntimeTestCaseResult {
        let start = Date()
        let baseline = """
        # System Assets — Central Instruction Index
        Routing guide.

        ---

        # ASSIST IDENTITY & OPERATING NORMS
        You are Assist.

        ---

        # SAFEGUARDS — NON-NEGOTIABLE SAFETY RULES
        Never exfiltrate secrets.
        """
        let out = AssistSystemPromptSections.runtimeInstructions(
            from: baseline,
            repositoryInstructions: nil,
            toolkit: "Cloud",
            objective: "Fix the build failure in my Swift project"
        )
        let passed = out.contains("ASSIST IDENTITY & OPERATING NORMS")
            && out.contains("SAFEGUARDS — NON-NEGOTIABLE SAFETY RULES")
            && out.contains("Never exfiltrate secrets.")
            && out.contains("Active Tool Protocol — Cloud Toolkit")
        return result(testName: "SDK Instructions: Baseline Preserved", passed: passed,
                      message: passed ? "Identity + Safeguards carried in full with toolkit protocol."
                                      : "Baseline was stripped from session instructions.", start: start)
    }

    /// Greetings must not load the instruction corpus at all.
    func testRuntimeInstructionsGreetingFastPath() -> RuntimeTestCaseResult {
        let start = Date()
        let baseline = "# ASSIST IDENTITY & OPERATING NORMS\nYou are Assist."
        let out = AssistSystemPromptSections.runtimeInstructions(
            from: baseline,
            repositoryInstructions: "## Some repo guidance",
            toolkit: "Cloud",
            objective: "Hello"
        )
        let passed = out.count < 1_000
            && !out.contains("ASSIST IDENTITY")
            && !out.contains("Task-Relevant Repository Instructions")
        return result(testName: "SDK Instructions: Greeting Fast Path", passed: passed,
                      message: passed ? "Greeting bypassed the instruction corpus."
                                      : "Greeting loaded instructions.", start: start)
    }

    // MARK: - Timeout error

    /// The timeout error's message must survive `localizedDescription`
    /// (LocalizedError conformance), never degrading to a generic string.
    func testTimeoutErrorLocalizedDescription() -> RuntimeTestCaseResult {
        let start = Date()
        let error: Error = AssistRequestTimeoutError.timedOut(180)
        let text = error.localizedDescription
        let passed = text.contains("timed out after 180 seconds")
            && !text.contains("couldn't be completed")
        return result(testName: "Timeout Error: Localized Message", passed: passed,
                      message: passed ? "Custom timeout message preserved: \"\(text.prefix(60))…\""
                                      : "Message degraded: \"\(text)\"", start: start)
    }

    // MARK: - Request generation

    func testRequestGenerationEquality() -> RuntimeTestCaseResult {
        let start = Date()
        let a = AssistRequestGeneration(3)
        let b = AssistRequestGeneration(3)
        let c = AssistRequestGeneration(4)
        let passed = a == b && a != c
        return result(testName: "Request Generation: Equality", passed: passed,
                      message: passed ? "Generation tokens compare by value."
                                      : "Generation equality broken.", start: start)
    }

    // MARK: - Queue envelope preservation

    /// A queued message must not silently lose the composer's task envelope
    /// (explicit skills / MCP servers / files), including across Codable
    /// round-trips.
    func testQueuedMessagePreservesEnvelope() -> RuntimeTestCaseResult {
        let start = Date()
        let envelope = AssistTaskEnvelope(
            userMessage: "Do the thing",
            explicitSkills: [],
            explicitMCPServers: ["my-mcp"],
            explicitFiles: []
        )
        let item = QueuedAssistMessage(content: "Do the thing", envelope: envelope)
        let preserved = item.envelope?.explicitMCPServers == ["my-mcp"]
            && item.envelope?.userMessage == "Do the thing"
        let roundTripped: Bool = {
            guard let data = try? JSONEncoder().encode(item),
                  let decoded = try? JSONDecoder().decode(QueuedAssistMessage.self, from: data) else {
                return false
            }
            return decoded.envelope?.explicitMCPServers == ["my-mcp"]
        }()
        let passed = preserved && roundTripped
        return result(testName: "Queue: Envelope Preserved", passed: passed,
                      message: passed ? "Envelope survived queueing and Codable round-trip."
                                      : "Envelope lost (preserved=\(preserved), roundTripped=\(roundTripped)).",
                      start: start)
    }
}
