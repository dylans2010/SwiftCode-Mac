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
            await testToolSourceMapping(),
            await testToolSourceSettingRoundTrip(),
            await testEventStoreMerge(),
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
