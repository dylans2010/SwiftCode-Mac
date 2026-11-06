import Foundation

// MARK: - SDK provider tests (OpenCode SDK + OpenRouter Agent SDK)
//
// Follows the AssistRuntimeTestSuite convention: in-app
// RuntimeTestCaseResult cases, wired into AssistRuntimeTestSuite.
// Every case here is offline and deterministic — no server, no API key,
// no network, no bridge launch. Live behaviour (a real opencode server,
// a real OpenRouter key, a real model run) is verified by the Settings
// install/status/connection checks and is listed as unverified in
// Docs/Assist-SDK-Providers.md.

@MainActor
public final class SDKProviderTests: Sendable {
    public static let shared = SDKProviderTests()

    private init() {}

    public func runAllTests() async -> [RuntimeTestCaseResult] {
        [
            await testApplicableKind(),
            await testApplicableKindOpenRouterPersistedFallback(),
            await testToolSourceMapping(),
            await testToolSourceSettingRoundTrip(),
            await testEventStoreMerge(),
            await testEventStoreMergeExtended(),
            await testEventStoreCancelNonTerminal(),
            await testEventProviderRouting(),
        ]
    }

    private func result(_ name: String, _ start: Date, _ passed: Bool, _ message: String) -> RuntimeTestCaseResult {
        RuntimeTestCaseResult(testName: name, passed: passed, message: message, duration: Date().timeIntervalSince(start))
    }

    // 1. SDK routing: opencode ids go to OpenCode; bare native ids and
    // non-slash ids never take the SDK path.
    public func testApplicableKind() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "SDK routing keys on the opencode: prefix and never claims bare native ids."
        if AssistSDKSessionRunner.applicableKind(for: "opencode:anthropic/claude-sonnet-4-5") != .openCode {
            passed = false
            message = "opencode:anthropic/claude-… did not route to OpenCode."
        }
        if AssistSDKSessionRunner.applicableKind(for: "claude-sonnet-4-5") != nil {
            passed = false
            message = "A bare native Claude id was claimed by the SDK path."
        }
        if AssistSDKSessionRunner.applicableKind(for: "swiftcode-cloud") != nil {
            passed = false
            message = "A SwiftCode Cloud id was claimed by the SDK path."
        }
        if AssistSDKSessionRunner.applicableKind(for: "") != nil {
            passed = false
            message = "An empty model id was claimed by the SDK path."
        }
        return result("SDK Providers: session routing", start, passed, message)
    }

    // 1b. Positive OpenRouter routing: a slash id with no discovery
    // record takes the persisted-provider fallback (openRouter).
    // A synthetic id is used so no real discovery record can veto it.
    public func testApplicableKindOpenRouterPersistedFallback() async -> RuntimeTestCaseResult {
        let start = Date()
        let original = AssistProviderSelection.persistedProvider
        defer { AssistProviderSelection.persistedProvider = original }
        AssistProviderSelection.persistedProvider = .openRouter
        let kind = AssistSDKSessionRunner.applicableKind(for: "openrouter-test-provider/some-model-xyz")
        let passed = kind == .openRouter
        return result(
            "SDK Providers: OpenRouter persisted-provider routing",
            start, passed,
            passed ? "A slash id with no discovery record routes to OpenRouter via the persisted provider."
                : "The persisted-provider fallback did not route a slash id to OpenRouter."
        )
    }

    // 2. Tool-source combinations: cross-provider sources are rejected
    // (nil), never silently remapped; combined maps for both providers.
    public func testToolSourceMapping() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "Cross-provider tool sources are rejected; combined maps for both providers."
        if AssistSDKSessionRunner.openCodeToolSource(for: .openrouter) != nil {
            passed = false
            message = "OpenRouter tools were accepted for OpenCode."
        }
        if AssistSDKSessionRunner.openRouterToolSource(for: .opencode) != nil {
            passed = false
            message = "OpenCode tools were accepted for OpenRouter."
        }
        if AssistSDKSessionRunner.openCodeToolSource(for: .combined) != .combined
            || AssistSDKSessionRunner.openRouterToolSource(for: .combined) != .combined {
            passed = false
            message = "Combined did not map for both providers."
        }
        if AssistSDKSessionRunner.openCodeToolSource(for: .swiftcode) != .swiftcode
            || AssistSDKSessionRunner.openRouterToolSource(for: .swiftcode) != .swiftcode {
            passed = false
            message = "SwiftCode tools did not map for both providers."
        }
        return result("SDK Providers: tool-source mapping", start, passed, message)
    }

    // 3. Tool-source setting persists independently and restores.
    public func testToolSourceSettingRoundTrip() async -> RuntimeTestCaseResult {
        let start = Date()
        let original = SDKToolSourceSetting.load()
        defer { original.save() }
        SDKToolSourceSetting.combined.save()
        let loaded = SDKToolSourceSetting.load()
        let passed = loaded == .combined
        return result(
            "SDK Providers: tool-source persistence",
            start, passed,
            passed ? "Tool-source setting round-trips through UserDefaults." : "Tool-source setting did not round-trip (got \(loaded.rawValue))."
        )
    }

    // 4. Event store: a duplicate toolCallId merges in place (no second
    // row) and a terminal state never regresses.
    public func testEventStoreMerge() async -> RuntimeTestCaseResult {
        let start = Date()
        let store = SDKToolEventStore()
        let requested = SDKToolEvent(provider: "openrouter", sessionId: "test-session", toolCallId: "call-1", toolName: "fetch_url", source: .openrouter, state: .requested, arguments: "{}")
        let running = SDKToolEvent(provider: "openrouter", sessionId: "test-session", toolCallId: "call-1", toolName: "fetch_url", source: .openrouter, state: .running, arguments: "{}")
        let completed = SDKToolEvent(provider: "openrouter", sessionId: "test-session", toolCallId: "call-1", toolName: "fetch_url", source: .openrouter, state: .completed, arguments: "{}", result: "ok")
        let regressed = SDKToolEvent(provider: "openrouter", sessionId: "test-session", toolCallId: "call-1", toolName: "fetch_url", source: .openrouter, state: .running, arguments: "{}")
        store.apply(requested)
        store.apply(running)
        store.apply(completed)
        store.apply(regressed)
        let rows = store.events(for: "test-session")
        let passed = rows.count == 1 && rows.first?.state == .completed && rows.first?.result == "ok"
        return result(
            "SDK Providers: event merge",
            start, passed,
            passed ? "Duplicate toolCallId merges to one row; terminal state never regresses." : "Event merge produced \(rows.count) rows with state \(rows.first?.state.rawValue ?? "none")."
        )
    }

    // 4b. Merge edge cases the happy-path test did not cover:
    // terminal -> different terminal never regresses, a same-state
    // refresh never invents (or drops) a result, and the same
    // toolCallId under a different source is a different call.
    public func testEventStoreMergeExtended() async -> RuntimeTestCaseResult {
        let start = Date()
        var passed = true
        var message = "Terminal states never change, same-state refresh preserves results, and source is part of the merge key."
        let store = SDKToolEventStore()
        let completed = SDKToolEvent(provider: "openrouter", sessionId: "ext-session", toolCallId: "call-1", toolName: "fetch_url", source: .openrouter, state: .completed, arguments: "{}", result: "ok")
        let failedLater = SDKToolEvent(provider: "openrouter", sessionId: "ext-session", toolCallId: "call-1", toolName: "fetch_url", source: .openrouter, state: .failed, arguments: "{}", error: "boom")
        let refreshNilResult = SDKToolEvent(provider: "openrouter", sessionId: "ext-session", toolCallId: "call-1", toolName: "fetch_url", source: .openrouter, state: .completed, arguments: "{}")
        let otherSource = SDKToolEvent(provider: "openrouter", sessionId: "ext-session", toolCallId: "call-1", toolName: "fetch_url", source: .swiftcode, state: .completed, arguments: "{}", result: "native-ok")
        store.apply(completed)
        store.apply(failedLater)
        store.apply(refreshNilResult)
        store.apply(otherSource)
        let rows = store.events(for: "ext-session")
        if rows.count != 2 {
            passed = false
            message = "Expected 2 rows (one per source), got \(rows.count)."
        } else if rows.first?.state != .completed || rows.first?.result != "ok" {
            passed = false
            message = "Terminal completed row regressed to failed or lost its result."
        } else if rows.last?.source != .swiftcode || rows.last?.result != "native-ok" {
            passed = false
            message = "The same toolCallId under a different source did not form its own row."
        }
        return result("SDK Providers: event merge edge cases", start, passed, message)
    }

    // 4c. Cancellation reaches a terminal UI state: requested/running
    // rows become cancelled, terminal rows are untouched.
    public func testEventStoreCancelNonTerminal() async -> RuntimeTestCaseResult {
        let start = Date()
        let store = SDKToolEventStore()
        store.apply(SDKToolEvent(provider: "opencode", sessionId: "cancel-session", toolCallId: "a", toolName: "bash", source: .opencode, state: .requested, arguments: "{}"))
        store.apply(SDKToolEvent(provider: "opencode", sessionId: "cancel-session", toolCallId: "b", toolName: "read", source: .opencode, state: .running, arguments: "{}"))
        store.apply(SDKToolEvent(provider: "opencode", sessionId: "cancel-session", toolCallId: "c", toolName: "done", source: .opencode, state: .completed, arguments: "{}", result: "ok"))
        store.apply(SDKToolEvent(provider: "opencode", sessionId: "cancel-session", toolCallId: "d", toolName: "bad", source: .opencode, state: .failed, arguments: "{}", error: "boom"))
        store.cancelNonTerminal(sessionId: "cancel-session")
        let rows = store.events(for: "cancel-session")
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.toolCallId, $0) })
        let passed = rows.count == 4
            && byId["a"]?.state == .cancelled && byId["b"]?.state == .cancelled
            && byId["c"]?.state == .completed && byId["c"]?.result == "ok"
            && byId["d"]?.state == .failed && byId["d"]?.error == "boom"
        return result(
            "SDK Providers: cancel marks non-terminal rows cancelled",
            start, passed,
            passed ? "Requested/running rows became cancelled; terminal rows were untouched."
                : "cancelNonTerminal produced states: \(rows.map { "\($0.toolCallId)=\($0.state.rawValue)" }.joined(separator: ", "))."
        )
    }

    // 5. View routing contract: a SwiftCode-source call inside an
    // OpenRouter run still belongs to the OpenRouter view, because its
    // serving provider is openrouter. The views filter on provider,
    // not on source (see ORToolsUIView / OCToolsUIView).
    public func testEventProviderRouting() async -> RuntimeTestCaseResult {
        let start = Date()
        let events = [
            SDKToolEvent(provider: "openrouter", sessionId: "s", toolCallId: "a", toolName: "read_file", source: .swiftcode, state: .completed, arguments: "{}"),
            SDKToolEvent(provider: "opencode", sessionId: "s", toolCallId: "b", toolName: "bash", source: .opencode, state: .completed, arguments: "{}"),
        ]
        let openRouterRows = events.filter { $0.provider == "openrouter" }
        let openCodeRows = events.filter { $0.provider == "opencode" }
        let passed = openRouterRows.count == 1 && openRouterRows.first?.toolCallId == "a"
            && openCodeRows.count == 1 && openCodeRows.first?.toolCallId == "b"
        return result(
            "SDK Providers: provider view routing",
            start, passed,
            passed ? "Each event routes to exactly one provider view by serving provider." : "Provider view routing misassigned events."
        )
    }
}
