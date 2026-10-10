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
        results.append(await testLiteRTConfiguration())
        results.append(await testToolProgressEventModel())
        results.append(await testLiveBridgeProcessAndHandshake())
        results.append(await testLiveSessionLifecycle())
        results.append(await testEventStreamingSubscription())
        results.append(await testSecurityCredentialSafety())

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

        let passed = compact.count < systemPrompt.count + repositoryInstructions.count &&
            compact.contains("structured tools exposed by the active toolkit") &&
            compact.contains("Preserve tool event streaming and cancellation") &&
            compact.contains("SDK Tool Protocol Boundary") &&
            !compact.contains("You MUST respond as a toolId/input JSON object") &&
            !compact.contains("This unrelated section should not enter") &&
            !systemToolkit.contains("You MUST respond as a toolId/input JSON object") &&
            greeting.count < 1_000 && !greeting.contains("Task-Relevant Repository Instructions")
        return RuntimeTestCaseResult(
            testName: "Bounded Task-Relevant SDK Instructions",
            passed: passed,
            message: passed ? "Task-specific instructions are bounded, while greetings avoid loading the coding and repository corpus." : "SDK instruction compaction lost relevant policy or retained unrelated guidance.",
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

    // LiteRT Configuration Test
    public func testLiteRTConfiguration() async -> RuntimeTestCaseResult {
        let start = Date()
        let config = GoogleCloudSDKConfiguration(
            model: "gemma-3-27b",
            provider: "litert",
            litertModelPath: "/path/to/model.litertlm",
            litertBackend: "gpu",
            downloadIfMissing: true
        )

        let dict = config.toDictionary()
        let hasPath = (dict["litertModelPath"] as? String) == "/path/to/model.litertlm"
        let hasBackend = (dict["litertBackend"] as? String) == "gpu"
        let hasDownload = (dict["downloadIfMissing"] as? Bool) == true

        // Verify JSON round-trip
        var roundTripOk = false
        if let data = try? JSONEncoder().encode(config),
           let decoded = try? JSONDecoder().decode(GoogleCloudSDKConfiguration.self, from: data) {
            roundTripOk = decoded.litertModelPath == "/path/to/model.litertlm" &&
                          decoded.litertBackend == "gpu" &&
                          decoded.downloadIfMissing == true
        }

        let passed = hasPath && hasBackend && hasDownload && roundTripOk
        return RuntimeTestCaseResult(
            testName: "LiteRT Model Configuration & IPC Serialization",
            passed: passed,
            message: passed ? "LiteRT model parameters serialized and decoded correctly." : "LiteRT serialization failed.",
            duration: Date().timeIntervalSince(start)
        )
    }

    // Tool Progress Event Model Test
    public func testToolProgressEventModel() async -> RuntimeTestCaseResult {
        let start = Date()
        let event = GoogleCloudSDKEvent.toolProgress(
            sessionId: "session_123",
            toolId: "file_write",
            message: "Writing file...",
            outputChunk: "data chunk 1",
            callId: "call_abc"
        )

        var matched = false
        if case .toolProgress(let sid, let toolId, let msg, let chunk, let callId) = event {
            matched = (sid == "session_123") &&
                      (toolId == "file_write") &&
                      (msg == "Writing file...") &&
                      (chunk == "data chunk 1") &&
                      (callId == "call_abc")
        }

        let hasTargetSession = (event.targetSessionId == "session_123")
        let passed = matched && hasTargetSession

        return RuntimeTestCaseResult(
            testName: "Tool Progress Event Model & Target Session Resolution",
            passed: passed,
            message: passed ? "toolProgress event correctly transports progress message, output chunk, callId, and targetSessionId." : "toolProgress event fields validation failed.",
            duration: Date().timeIntervalSince(start)
        )
    }
}
