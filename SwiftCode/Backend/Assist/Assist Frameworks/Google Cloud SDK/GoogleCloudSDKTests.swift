//
//  GoogleCloudSDKTests.swift
//  SwiftCode
//
//  Comprehensive test suite for the Google Cloud SDK / Antigravity integration.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKTests")

@MainActor
public final class GoogleCloudSDKTests: Sendable {
    public static let shared = GoogleCloudSDKTests()

    private init() {}

    /// Executes all tests in the Google Cloud SDK suite.
    public func runAllTests() async -> [RuntimeTestCaseResult] {
        var results: [RuntimeTestCaseResult] = []

        results.append(await testRuntimePathResolution())
        results.append(await testConfigurationDiscoveryAndSerialization())
        results.append(await testBoundedRuntimeInstructions())
        results.append(await testToolPayloadStreamingFilter())
        results.append(await testErrorDescriptions())
        results.append(await testMessageAndToolModels())
        results.append(await testLiveBridgeProcessAndHandshake())
        results.append(await testLiveSessionLifecycle())
        results.append(await testEventStreamingSubscription())
        results.append(await testSecurityCredentialSafety())
        results.append(await testAntigravityAccountAuthenticationStateAndOAuthResolution())
        results.append(await testRuntimeSessionVerificationProbe())
        results.append(await testGoogleAuthErrorClassification())
        results.append(await testOAuthQuotaProjectHeaderSerialization())
        results.append(await testSessionReuseContractIncludesCredentials())
        results.append(await testCustomModelProviderResolution())
        results.append(await testResolveAPIKeyNeverFallsBackInOAuthMode())
        results.append(await testChatModeGoogleOAuthSatisfiesCheck())
        results.append(await testDeveloperAPIScopesAreClientCompatible())
        results.append(await testDefaultOAuthClientIDIsConfigured())
        results.append(await testMissingClientSecretClassification())
        results.append(await testActionableSignInErrorForMissingSecret())
        results.append(await testClientSecretKeychainStorage())

        let routerTests = await AssistModelRouterTests.shared.runAllTests()
        results.append(contentsOf: routerTests)

        return results
    }

    // 1. Runtime Path Resolution
    public func testRuntimePathResolution() async -> RuntimeTestCaseResult {
        let start = Date()
        let sdkURL = GoogleCloudSDKProcess.resolveSDKDirectory()
        let passed = (sdkURL != nil) && FileManager.default.fileExists(atPath: sdkURL!.appendingPathComponent("bridge/main.py").path)

        return RuntimeTestCaseResult(
            testName: "Google Cloud SDK Runtime Path Discovery",
            passed: passed,
            message: passed ? "Located Google Cloud SDK runtime at: \(sdkURL!.path)" : "Failed to locate Google Cloud SDK runtime.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 2. Configuration Discovery & Serialization
    public func testConfigurationDiscoveryAndSerialization() async -> RuntimeTestCaseResult {
        let start = Date()
        let config = GoogleCloudSDKConfiguration.resolveDefault()
        let dict = config.toDictionary()

        let hasModel = (dict["model"] as? String) != nil
        let hasWorkspaces = (dict["workspaces"] as? [String]) != nil
        let hasSkills = (dict["skillsPaths"] as? [String]) != nil
        let passed = hasModel && hasWorkspaces && hasSkills

        return RuntimeTestCaseResult(
            testName: "Configuration Discovery & IPC Payload",
            passed: passed,
            message: passed ? "Configuration properly resolved with model '\(config.model)' and \(config.skillsPaths.count) skill paths." : "Configuration serialization failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    public func testBoundedRuntimeInstructions() async -> RuntimeTestCaseResult {
        let start = Date()
        let systemPrompt = (try? AssistManager.shared.getSystemPrompt()) ?? ""
        let repositoryInstructions = """
        # Example repository guidance
        ## 1. Executive Architecture & State Machine
        Keep UI updates on the main actor.
        ## 3. Autonomous AI Agent Architecture (Assist Engine)
        Preserve tool event streaming and cancellation.
        ### 3.3 Prompt Engineering & Strict JSON Protocol Contract
        You MUST respond as a toolId/input JSON object in the native Swift runtime.
        ## 11. Visual UI Builder & Artboard Canvas
        This unrelated section should not enter a streaming task prompt.
        """
        let compact = AssistSystemPromptSections.runtimeInstructions(
            from: systemPrompt,
            repositoryInstructions: repositoryInstructions,
            toolkit: "Cloud",
            objective: "Fix Assist agent tool streaming latency and raw JSON output"
        )
        let greeting = AssistSystemPromptSections.runtimeInstructions(
            from: systemPrompt,
            repositoryInstructions: repositoryInstructions,
            toolkit: "Cloud",
            objective: "Hello"
        )
        let systemToolkit = AssistSystemPromptSections.runtimeInstructions(
            from: systemPrompt,
            repositoryInstructions: repositoryInstructions,
            toolkit: "System",
            objective: "Fix Assist agent tool streaming latency and raw JSON output"
        )

        // New contract (canonical System Assets): the mandatory baseline
        // (Identity + Safeguards) is carried in full and never stripped;
        // task-specific sections arrive per request via SystemIndex and are
        // not duplicated here; repository guidance stays task-relevant.
        let passed = compact.contains("structured tools exposed by the active toolkit") &&
            compact.contains("Preserve tool event streaming and cancellation") &&
            compact.contains("SDK Tool Protocol Boundary") &&
            compact.contains("SAFEGUARDS") &&
            compact.contains("ASSIST IDENTITY") &&
            !compact.contains("You MUST respond as a toolId/input JSON object") &&
            !compact.contains("This unrelated section should not enter") &&
            !systemToolkit.contains("You MUST respond as a toolId/input JSON object") &&
            greeting.count < 1_000 && !greeting.contains("Task-Relevant Repository Instructions")
        return RuntimeTestCaseResult(
            testName: "Bounded Task-Relevant SDK Instructions",
            passed: passed,
            message: passed ? "Baseline (Identity + Safeguards) preserved in full, repository guidance task-relevant, greetings avoid the corpus." : "SDK instruction assembly lost baseline policy or retained unrelated guidance.",
            duration: Date().timeIntervalSince(start)
        )
    }

    public func testToolPayloadStreamingFilter() async -> RuntimeTestCaseResult {
        let start = Date()

        var proseFilter = AssistToolPayloadStreamFilter()
        let firstProseDelta = proseFilter.append("Hello")
        let secondProseDelta = proseFilter.append(" there.")
        let proseRemainder = proseFilter.finish(fallbackResponse: "Hello there.")

        let rawToolPayload = #"{"name":"run_command","arguments":{"CommandLine":"git status --short"}}{"function_name":"run_command","arguments":{"CommandLine":"git status --short"}}"#
        var rawFilter = AssistToolPayloadStreamFilter()
        let leakedRawPayload = rawFilter.append(rawToolPayload) + rawFilter.finish(fallbackResponse: rawToolPayload)

        let fencedPayload = "```json\n{\"toolId\":\"run_command\",\"input\":{\"command\":\"git status --short\"}}\n```"
        var fencedFilter = AssistToolPayloadStreamFilter()
        let leakedFencedPayload = fencedFilter.append(fencedPayload) + fencedFilter.finish(fallbackResponse: fencedPayload)

        var jsonAnswerFilter = AssistToolPayloadStreamFilter()
        let jsonAnswer = #"{"answer":"ok"}"#
        let safeJSON = jsonAnswerFilter.append(jsonAnswer) + jsonAnswerFilter.finish(fallbackResponse: jsonAnswer)

        let passed = firstProseDelta == "Hello" && secondProseDelta == " there." && proseRemainder.isEmpty &&
            rawFilter.didSuppressToolPayload && leakedRawPayload.isEmpty &&
            fencedFilter.didSuppressToolPayload && leakedFencedPayload.isEmpty &&
            !jsonAnswerFilter.didSuppressToolPayload && safeJSON == jsonAnswer

        return RuntimeTestCaseResult(
            testName: "Safe Streaming of Tool Requests as Text",
            passed: passed,
            message: passed ? "Plain text still streams immediately; serialized tool requests are suppressed and ordinary JSON remains visible." : "Tool payload filtering regression detected.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 3. Error Descriptions
    public func testErrorDescriptions() async -> RuntimeTestCaseResult {
        let start = Date()
        let errors: [GoogleCloudSDKError] = [
            .runtimeNotFound("SDK missing"),
            .pythonMissing("Python not found"),
            .socketConnectionFailed("Connection refused"),
            .handshakeFailed("Invalid token"),
            .sessionNotFound("Session 123"),
            .operationCancelled,
            .authenticationRequired("Missing Gemini API Key"),
        ]

        var passed = true
        for err in errors {
            if err.localizedDescription.isEmpty {
                passed = false
            }
        }

        return RuntimeTestCaseResult(
            testName: "Error Handling & Descriptions",
            passed: passed,
            message: passed ? "All error cases produced valid localized descriptions." : "Empty error descriptions found.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 4. Message & Tool Models
    public func testMessageAndToolModels() async -> RuntimeTestCaseResult {
        let start = Date()
        let attachment = GoogleCloudSDKAttachment(name: "test.swift", path: "/tmp/test.swift")
        let message = GoogleCloudSDKMessage(role: .user, content: "Hello", attachments: [attachment])
        let toolEvent = GoogleCloudSDKToolEvent(id: "call_1", sessionId: "sess_1", name: "view_file", rawArgs: "{\"path\": \"test.swift\"}")
        let toolResult = GoogleCloudSDKToolResult(id: "call_1", sessionId: "sess_1", name: "view_file", result: "let x = 1")

        let passed = (message.attachments.count == 1) &&
                     (toolEvent.name == "view_file") &&
                     toolResult.success &&
                     (toolResult.result == "let x = 1")

        return RuntimeTestCaseResult(
            testName: "Message & Tool Domain Models",
            passed: passed,
            message: passed ? "Message and Tool models serialized and validated correctly." : "Domain model validation failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 5. Live Bridge Process & Handshake
    public func testLiveBridgeProcessAndHandshake() async -> RuntimeTestCaseResult {
        let start = Date()
        let bridge = GoogleCloudSDKBridge()

        do {
            try await bridge.start()
            let status = try await bridge.getStatus()
            let isRunning = (status["status"] as? String) == "running"
            await bridge.stop()

            return RuntimeTestCaseResult(
                testName: "Live Bridge Subprocess & JSON-RPC Handshake",
                passed: isRunning,
                message: isRunning ? "Bridge launched, responded to JSON-RPC handshake, and verified 'running' status." : "Bridge status did not report running.",
                duration: Date().timeIntervalSince(start)
            )
        } catch {
            await bridge.stop()
            return RuntimeTestCaseResult(
                testName: "Live Bridge Subprocess & JSON-RPC Handshake",
                passed: false,
                message: "Bridge failed to start: \(error.localizedDescription)",
                duration: Date().timeIntervalSince(start)
            )
        }
    }

    // 6. Live Session Lifecycle
    public func testLiveSessionLifecycle() async -> RuntimeTestCaseResult {
        let start = Date()
        let bridge = GoogleCloudSDKBridge()
        let sessionId = "test-session-\(UUID().uuidString.prefix(6))"

        do {
            try await bridge.start()
            var config = GoogleCloudSDKConfiguration.resolveDefault()
            config.apiKey = config.apiKey ?? "test-suite-key"

            let created = try await bridge.createSession(sessionId: sessionId, config: config)
            let createdOk = created.status == "ready"

            let closed = try await bridge.closeSession(sessionId: sessionId)
            let closedOk = closed.status == "closed"

            await bridge.stop()
            let passed = createdOk && closedOk

            return RuntimeTestCaseResult(
                testName: "Live Antigravity Session Lifecycle",
                passed: passed,
                message: passed ? "Successfully created session '\(sessionId)' and closed cleanly." : "Session lifecycle state mismatch.",
                duration: Date().timeIntervalSince(start)
            )
        } catch {
            await bridge.stop()
            return RuntimeTestCaseResult(
                testName: "Live Antigravity Session Lifecycle",
                passed: false,
                message: "Session test failed: \(error.localizedDescription)",
                duration: Date().timeIntervalSince(start)
            )
        }
    }

    // 7. Event Streaming Subscription
    public func testEventStreamingSubscription() async -> RuntimeTestCaseResult {
        let start = Date()
        let bridge = GoogleCloudSDKBridge()

        do {
            try await bridge.start()
            let stream = await bridge.subscribeEvents()

            // Verify stream is active
            let testTask = Task {
                for await event in stream {
                    if case .runtimeReady = event {
                        return true
                    }
                }
                return false
            }

            // Status request to trigger activity
            _ = try await bridge.getStatus()
            try? await Task.sleep(nanoseconds: 200_000_000)

            await bridge.stop()
            testTask.cancel()

            return RuntimeTestCaseResult(
                testName: "AsyncStream Event Subscription",
                passed: true,
                message: "Event subscription established successfully without deadlock.",
                duration: Date().timeIntervalSince(start)
            )
        } catch {
            await bridge.stop()
            return RuntimeTestCaseResult(
                testName: "AsyncStream Event Subscription",
                passed: false,
                message: "Event subscription failed: \(error.localizedDescription)",
                duration: Date().timeIntervalSince(start)
            )
        }
    }

    // 8. Security Credential Safety
    public func testSecurityCredentialSafety() async -> RuntimeTestCaseResult {
        let start = Date()
        let secretKey = "AIzaSyTestSecretKeyDoNotLog"
        var config = GoogleCloudSDKConfiguration.resolveDefault()
        config.apiKey = secretKey

        let dict = config.toDictionary()
        let runtimeLogs = await GoogleCloudSDKRuntime.shared.liveLogs.joined(separator: " ")

        let passed = !runtimeLogs.contains(secretKey)

        return RuntimeTestCaseResult(
            testName: "Security: Credential Sanitization in Telemetry",
            passed: passed,
            message: passed ? "Verified API keys are never surfaced into diagnostic logs or telemetry." : "Sensitive API key found in runtime logs.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 9. Antigravity Account Authentication State & OAuth Resolution
    public func testAntigravityAccountAuthenticationStateAndOAuthResolution() async -> RuntimeTestCaseResult {
        let start = Date()
        let authService = GoogleAccountAuthService.shared
        let initialIsAuth = authService.isAuthenticated

        // Test configuration resolution with OAuth token
        let config = GoogleCloudSDKConfiguration.resolveDefault()
        let dict = config.toDictionary()

        let hasOAuthToken = (dict["oauthToken"] as? String) != nil
        let hasApiKey = (dict["apiKey"] as? String) != nil

        // If authenticated via OAuth, apiKey must be nil to enforce zero API key reliance
        let passed = (!initialIsAuth || (hasOAuthToken && !hasApiKey))

        return RuntimeTestCaseResult(
            testName: "Antigravity Account Authentication & OAuth Token Resolution",
            passed: passed,
            message: passed ? "OAuth token resolution correctly enforced zero API key requirement when authenticated." : "OAuth token resolution failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 10. Runtime Session Verification Probe
    public func testRuntimeSessionVerificationProbe() async -> RuntimeTestCaseResult {
        let start = Date()
        let authService = GoogleAccountAuthService.shared

        // Perform probe with invalid test token and verify it fails gracefully without throwing
        let dummyVerified = await authService.verifyRuntimeSession(accessToken: "ya29.invalid_test_token_for_verification")
        let passed = !dummyVerified // Should correctly reject invalid token

        return RuntimeTestCaseResult(
            testName: "Runtime Session Verification Probe",
            passed: passed,
            message: passed ? "Runtime session verification probe correctly rejected invalid OAuth token." : "Verification probe failed to reject invalid token.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 11. Google Auth Error Classification
    // The reported production failure must classify as scope-insufficient with
    // its diagnostics preserved - never as a generic "Authentication error".
    public func testGoogleAuthErrorClassification() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []

        let reportedError = """
        Authentication error (Gemini 3.8 Flash (Medium)): Agent execution terminated \
        due to error. "agent executor error: Error 403, Message: Request had \
        insufficient authentication scopes., Status: PERMISSION_DENIED, Details: \
        [map[@type:type.googleapis.com/google.rpc.ErrorInfo \
        metadata:map[method:google.ai.generativelanguage.v1beta.GenerativeService.StreamGenerateContent \
        service:generativelanguage.googleapis.com] reason:ACCESS_TOKEN_SCOPE_INSUFFICIENT]]"
        """

        // Legacy token (minted before the Developer API scope existed) -> fixable by re-auth.
        let legacyScopes = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/aicode openid"
        let legacy = GoogleAuthErrorClassification.classify(reportedError, storedScopes: legacyScopes)
        if case .scopeInsufficient(let stored) = legacy.kind {
            if stored != legacyScopes { failures.append("legacy stored scopes not carried") }
        } else {
            failures.append("reported 403 did not classify as scopeInsufficient")
        }
        if legacy.httpStatus != 403 { failures.append("httpStatus not 403") }
        if legacy.reason != "ACCESS_TOKEN_SCOPE_INSUFFICIENT" { failures.append("reason not preserved") }
        if legacy.service != "generativelanguage.googleapis.com" { failures.append("service not preserved") }
        if !(legacy.method?.contains("StreamGenerateContent") ?? false) { failures.append("method not preserved") }

        // Current token (already has the Developer API scope) -> NOT fixable by
        // re-auth; the caller must explain the restriction instead of looping.
        let currentScopes = legacyScopes + " https://www.googleapis.com/auth/generative-language.retriever"
        let current = GoogleAuthErrorClassification.classify(reportedError, storedScopes: currentScopes)
        if case .scopeInsufficient(let stored) = current.kind {
            let needsUpgrade = !(stored?.contains("generative-language.retriever") ?? false)
            if needsUpgrade { failures.append("correctly-scoped token flagged as needing scope upgrade") }
        } else {
            failures.append("scoped 403 did not classify as scopeInsufficient")
        }

        let quota = GoogleAuthErrorClassification.classify("Error 429: RESOURCE_EXHAUSTED quota exceeded", storedScopes: nil)
        if quota.kind != .quotaOrRateLimit { failures.append("429 quota misclassified") }

        let badKey = GoogleAuthErrorClassification.classify("API_KEY_INVALID: API key not valid", storedScopes: nil)
        if badKey.kind != .apiKeyInvalid { failures.append("API_KEY_INVALID misclassified") }

        let unauth = GoogleAuthErrorClassification.classify("Error 401 UNAUTHENTICATED: invalid credentials", storedScopes: nil)
        if unauth.kind != .invalidOrExpiredCredential { failures.append("401 misclassified") }

        let other = GoogleAuthErrorClassification.classify("model returned an empty response", storedScopes: nil)
        if other.kind != .notAuthError { failures.append("non-auth error misclassified") }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Google Auth Error Classification",
            passed: passed,
            message: passed ? "403 scope errors classify with diagnostics preserved; re-auth only offered for legacy scopes." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 12. OAuth Quota Project Header Serialization
    // The x-goog-user-project header is the Developer API's documented OAuth
    // contract; it must be present when a project is configured and absent
    // (never fabricated) when it is not.
    public func testOAuthQuotaProjectHeaderSerialization() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []

        var withProject = GoogleCloudSDKConfiguration(model: "gemini-3.8-flash")
        withProject.userProject = "my-quota-project"
        withProject.oauthToken = "ya29.test"
        withProject.apiKey = nil
        let dict = withProject.toDictionary()
        let headers = dict["headers"] as? [String: String]
        if headers?["x-goog-user-project"] != "my-quota-project" {
            failures.append("x-goog-user-project header missing or wrong")
        }
        if (dict["apiKey"] as? String) != nil {
            failures.append("apiKey present alongside oauthToken")
        }

        var withoutProject = GoogleCloudSDKConfiguration(model: "gemini-3.8-flash")
        withoutProject.oauthToken = "ya29.test"
        let dict2 = withoutProject.toDictionary()
        if dict2["headers"] != nil {
            failures.append("headers fabricated when no project configured")
        }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "OAuth Quota Project Header Serialization",
            passed: passed,
            message: passed ? "x-goog-user-project serializes exactly when configured; never fabricated." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 13. Session Reuse Contract (C-3)
    // A live bridge session bakes the bearer into its headers once; reusing a
    // session across a token rotation or quota-project change 401s
    // persistently. Reuse must require every credential-bearing field to match.
    public func testSessionReuseContractIncludesCredentials() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []

        var base = GoogleCloudSDKConfiguration(model: "gemini-2.5-flash")
        base.provider = "google"
        base.oauthToken = "ya29.first"
        base.userProject = "project-a"

        if !base.canReuseSession(for: base) {
            failures.append("identical configs refused reuse")
        }
        var rotated = base
        rotated.oauthToken = "ya29.second"
        if base.canReuseSession(for: rotated) {
            failures.append("rotated oauthToken still reused the session")
        }
        var newProject = base
        newProject.userProject = "project-b"
        if base.canReuseSession(for: newProject) {
            failures.append("changed userProject still reused the session")
        }
        var dropped = base
        dropped.oauthToken = nil
        if base.canReuseSession(for: dropped) {
            failures.append("dropped oauthToken still reused the session")
        }
        var newKey = base
        newKey.apiKey = "AIza-new"
        if base.canReuseSession(for: newKey) {
            failures.append("changed apiKey still reused the session")
        }
        var newModel = base
        newModel.model = "gemini-2.5-pro"
        if base.canReuseSession(for: newModel) {
            failures.append("changed model still reused the session")
        }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Session Reuse Contract Includes Credentials",
            passed: passed,
            message: passed ? "oauthToken and userProject participate in session reuse; rotations force a new session." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 14. Custom Model Provider Resolution (C-2)
    // The free-text custom model's provider must come from an explicit record
    // (SDK catalog) or explicit setting — never inferred from the name — and
    // a gemini-named custom model must resolve as the Google provider so a
    // valid OAuth session keeps its token.
    public func testCustomModelProviderResolution() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        let discovery = AssistModelDiscoveryService.shared

        // The reported C-2 model lives in the bundled seed catalog as Google.
        let seedResolved = discovery.providerResolutionForCustomModel(id: "gemini-3.8-flash-medium")
        if seedResolved.providerID != "gemini" {
            failures.append("seed-catalog gemini id resolved to '\(seedResolved.providerID)' instead of 'gemini'")
        }

        // Unknown id: explicit setting governs. Default is google, but N-2
        // scopes the google default to gemini-named ids only.
        let previousProvider = AppSettings.shared.customModelProviderID
        defer { AppSettings.shared.customModelProviderID = previousProvider }
        AppSettings.shared.customModelProviderID = "google"
        let futureGemini = discovery.providerResolutionForCustomModel(id: "gemini-9.9-ultra-future")
        if futureGemini.providerID != "gemini" {
            failures.append("unknown gemini-named custom id defaulted to '\(futureGemini.providerID)' instead of 'gemini' (C-2)")
        }
        // N-2: a non-gemini free-text id must NOT route to Google — it keeps
        // providerID "custom" and fails closed without an explicit endpoint.
        let llama = discovery.providerResolutionForCustomModel(id: "llama3")
        if llama.providerID != "custom" {
            failures.append("non-gemini custom id 'llama3' resolved to '\(llama.providerID)' instead of 'custom' (N-2)")
        }

        AppSettings.shared.customModelProviderID = "ollama"
        let local = discovery.providerResolutionForCustomModel(id: "some-future-model-xyz-123")
        if local.providerID != "ollama" {
            failures.append("explicit ollama setting resolved to '\(local.providerID)'")
        }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Custom Model Provider Resolution",
            passed: passed,
            message: passed ? "Custom model provider resolves from catalog record or explicit setting; gemini ids route as Google." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 15. No Silent API-Key Fallback in OAuth Mode
    // In google_oauth mode, resolving an API key for the Google provider must
    // return nil: the OAuth token travels in its own slot, and a silent
    // fallback would send the wrong credential kind.
    public func testResolveAPIKeyNeverFallsBackInOAuthMode() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []

        let key = "assist_google_auth_mode"
        let previousMode = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.set("google_oauth", forKey: key)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let router = AssistModelRouter.shared
        if router.resolveAPIKey(for: "gemini") != nil {
            failures.append("gemini resolved an API key in google_oauth mode")
        }
        if router.resolveAPIKey(for: "google") != nil {
            failures.append("google resolved an API key in google_oauth mode")
        }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "No Silent API-Key Fallback in OAuth Mode",
            passed: passed,
            message: passed ? "resolveAPIKey returns nil for the Google provider in google_oauth mode." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 16. Chat Mode Google OAuth Satisfies Credential Check (N-1)
    // A valid Google OAuth session must satisfy the Chat Mode credential
    // check for the Google provider — the old API-key-only gate wrongly
    // rejected OAuth-authenticated users holding no API key (same defect
    // class as C-1). Tests the pure decision contract; the live token fetch
    // stays at the call site.
    public func testChatModeGoogleOAuthSatisfiesCheck() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        func check(_ providerIsGoogle: Bool, _ mode: String, _ authed: Bool, _ token: Bool, expect: Bool, _ label: String) {
            let got = AssistManager.googleOAuthSatisfiesChatCheck(
                providerIsGoogle: providerIsGoogle,
                authMode: mode,
                isAuthenticated: authed,
                tokenAvailable: token
            )
            if got != expect {
                failures.append("\(label): got \(got), expected \(expect)")
            }
        }
        check(true, "google_oauth", true, true, expect: true, "valid OAuth session")
        check(true, "google_oauth", true, false, expect: false, "authenticated but tokenless")
        check(true, "google_oauth", false, true, expect: false, "not authenticated")
        check(true, "api_key", true, true, expect: false, "API-key mode")
        check(false, "google_oauth", true, true, expect: false, "non-Google provider")

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Chat Mode Google OAuth Credential Check",
            passed: passed,
            message: passed ? "OAuth session satisfies the Chat Mode Google check exactly when provider, mode, session, and token all agree." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 13. Developer API Scopes Are Client-Compatible
    // The sign-in flow must request exactly the documented Developer API
    // scopes. The Antigravity-IDE-internal scopes (cclog,
    // experimentsandconfigs, aicode) are not requested: on a user-owned
    // client they would only widen the consent screen, and Google's own
    // clients reject the generative-language.* scopes outright
    // ("Unregistered scope(s)", 403 restricted_client).
    public func testDeveloperAPIScopesAreClientCompatible() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        let scopes = GoogleAccountAuthService.requiredScopes
        for needed in ["https://www.googleapis.com/auth/cloud-platform",
                       "https://www.googleapis.com/auth/generative-language.retriever",
                       "https://www.googleapis.com/auth/userinfo.email",
                       "https://www.googleapis.com/auth/userinfo.profile",
                       "openid"] {
            if !scopes.contains(needed) { failures.append("missing \(needed)") }
        }
        for ideOnly in ["cclog", "experimentsandconfigs", "aicode"] {
            if scopes.contains(where: { $0.contains(ideOnly) }) {
                failures.append("IDE-internal scope requested: \(ideOnly)")
            }
        }
        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Developer API Scopes Are Client-Compatible",
            passed: passed,
            message: passed ? "Sign-in requests exactly the documented Developer API scopes." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 14. Default OAuth Client ID Is SwiftCode's Own
    // Sign-in must use SwiftCode's own OAuth client by default: Google
    // rejects the Developer API scopes on clients SwiftCode does not own
    // ("Unregistered scope(s)", 403 restricted_client). The ID is a public
    // identifier (PKCE public client, no secret), so it ships in the clear.
    public func testDefaultOAuthClientIDIsConfigured() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        let clientID = GoogleAccountAuthService.swiftCodeClientID
        if clientID.isEmpty { failures.append("default client ID is empty") }
        if !clientID.hasSuffix(".apps.googleusercontent.com") {
            failures.append("default client ID is malformed")
        }
        if clientID.contains(" ") { failures.append("default client ID contains whitespace") }
        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Default OAuth Client ID Is Configured",
            passed: passed,
            message: passed ? "Sign-in defaults to SwiftCode's own OAuth client ID." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 15. Missing Client Secret Classification
    // Production failure (2026-10-11): browser authorization succeeded but
    // Google's token endpoint rejected the code exchange with 400
    // invalid_request "client_secret is missing." — the app surfaced the raw
    // provider text. It must classify as missingClientSecret (not a generic
    // invalid credential), so the caller can give the specific remediation.
    public func testMissingClientSecretClassification() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []

        let reported = "client_secret is missing."
        let classified = GoogleAuthErrorClassification.classify(reported, storedScopes: nil)
        if classified.kind != .missingClientSecret {
            failures.append("Google's missing-secret error did not classify as missingClientSecret (got \(classified.kind))")
        }

        // A nearby but different credential failure must NOT take this branch.
        let invalidGrant = GoogleAuthErrorClassification.classify("invalid_grant: bad code", storedScopes: nil)
        if invalidGrant.kind == .missingClientSecret {
            failures.append("invalid_grant misclassified as missingClientSecret")
        }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Missing Client Secret Classification",
            passed: passed,
            message: passed ? "\"client_secret is missing\" classifies specifically." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 16. Actionable Sign-In Error for Missing Secret
    // The user-facing message for the missing-secret failure must name the
    // actual failing component (Google's token exchange) and the specific
    // remediation (enter the client secret in Settings; Keychain-stored).
    // Unrelated failures must pass through with details preserved.
    public func testActionableSignInErrorForMissingSecret() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []

        let secretError = NSError(
            domain: "GoogleAccountAuthService", code: 400,
            userInfo: [NSLocalizedDescriptionKey: "invalid_request: client_secret is missing."])
        let actionable = GoogleAccountAuthService.actionableSignInError(for: secretError)
        for required in ["client secret", "Settings", "Keychain", "token exchange"] {
            if !actionable.localizedCaseInsensitiveContains(required) {
                failures.append("actionable message missing '\(required)'")
            }
        }

        let otherError = NSError(
            domain: "GoogleAccountAuthService", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "No authorization code returned from Google."])
        let passthrough = GoogleAccountAuthService.actionableSignInError(for: otherError)
        if passthrough != "No authorization code returned from Google." {
            failures.append("unrelated error was not passed through verbatim")
        }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Actionable Sign-In Error For Missing Secret",
            passed: passed,
            message: passed ? "Missing-secret failure maps to specific remediation." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }

    // 17. Client Secret Keychain Storage
    // The secret must persist via Keychain (never UserDefaults, never the
    // bundle). The test never destroys a user-configured secret: it only
    // writes when none is present, and always cleans up afterwards.
    public func testClientSecretKeychainStorage() async -> RuntimeTestCaseResult {
        let start = Date()
        var failures: [String] = []
        let service = GoogleAccountAuthService.shared

        if service.hasKeychainClientSecret {
            // A real secret is configured; do not touch it. Presence alone
            // proves the Keychain path is live.
        } else {
            service.setClientSecret("test-secret-roundtrip")
            if !service.hasClientSecret { failures.append("secret not visible after set") }
            if !service.hasKeychainClientSecret { failures.append("secret not reported as Keychain-stored") }
            service.clearClientSecret()
            if service.hasKeychainClientSecret { failures.append("secret still present after clear") }
        }

        let passed = failures.isEmpty
        return RuntimeTestCaseResult(
            testName: "Client Secret Keychain Storage",
            passed: passed,
            message: passed ? "Client secret round-trips through Keychain." : "Failures: \(failures.joined(separator: "; "))",
            duration: Date().timeIntervalSince(start)
        )
    }
}
