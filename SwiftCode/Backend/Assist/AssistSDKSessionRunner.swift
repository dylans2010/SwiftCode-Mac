//  AssistSDKSessionRunner.swift
//  SwiftCode
//
//  Parent integration for the SDK-backed providers (OpenCode via
//  @opencode-ai/sdk, OpenRouter via @openrouter/agent). This file is the
//  single seam between AssistAgentSession and the two SDK provider
//  facades. It owns:
//
//  - Deciding whether a selected model takes the SDK path at all.
//  - Verifying the SDK runtime is installed (via SDKRuntimeManager) and
//    the bridge script is installed under the runtime directory.
//  - Building the run request from SwiftCode's real system prompt,
//    conversation history, and registered tool schemas.
//  - Executing SwiftCode-native tool calls through the native registry
//    (validation + tool-level permission checks via AssistContext) and
//    returning the model-facing payload — never a faked result.
//  - Publishing tool events into SDKToolEventStore under the Assist
//    session id, so ORToolsUIView / OCToolsUIView render the run.
//
//  What this file deliberately does NOT do:
//  - It never falls back to the HTTP clients (OpenCodeClient /
//    OpenRouterClient) when the SDK path is selected. A missing runtime,
//    missing key, or bridge failure is an actionable error naming
//    Assist Settings → SDK Providers, not a silent substitution.
//  - It does not apply the plan-based phase allowlist. That allowlist
//    belongs to the plan execution path; SDK runs are governed by
//    registry validation plus the tool-level permission checks carried
//    in AssistContext (the same checks plan tools go through at
//    execution time). This is documented in Docs/Assist-SDK-Providers.md.
//  - It does not own bridge processes: providers launch and terminate
//    their bridges (FoundationProcessBridgeLauncher, shared by both
//    providers); SDKRuntimeManager owns install / verification /
//    Settings status. `cancel()` terminates the active provider bridge.

import Foundation

/// Which SDK-backed runtime serves an Assist agent session, if any.
public enum SDKSessionKind: Sendable {
    case openCode
    case openRouter
}

public enum SDKSessionRunnerError: LocalizedError, Sendable {
    case runtimeNotInstalled(provider: SDKProvider, expected: String)
    case bridgeScriptMissing(provider: SDKProvider, fileName: String)
    case unsupportedToolSource(provider: String, source: String)
    case emptyFinalResponse

    public var errorDescription: String? {
        switch self {
        case .runtimeNotInstalled(let provider, let expected):
            return "\(provider.displayName) SDK runtime is not installed (expected \(provider.packageName)@\(expected)). Install it in Assist Settings → SDK Providers, then retry. No other provider was substituted."
        case .bridgeScriptMissing(let provider, let fileName):
            return "The \(provider.displayName) bridge script (\(fileName)) is missing from the app bundle. Rebuild the app from the current source, then retry."
        case .unsupportedToolSource(let provider, let source):
            return "Tool source \"\(source)\" is not supported for \(provider). Change the tool source in Assist Settings → SDK Providers; it was not silently changed for you."
        case .emptyFinalResponse:
            return "The SDK run completed without a final response. No text was posted."
        }
    }
}

/// Runs one SDK-backed Assist agent session. One instance serves one run
/// at a time; AssistAgentSession holds it for cancellation.
@MainActor
public final class AssistSDKSessionRunner {
    private var activeOpenCode: OpenCodeSDKProvider?
    private var activeOpenRouter: OpenRouterSDKProvider?

    public init() {}

    /// Returns the SDK kind for a selected model, or nil when the model
    /// must keep its existing (non-SDK) execution path. OpenCode ids
    /// (`opencode:provider/model`) are checked first so they can never
    /// be misclassified by the "/" heuristic below.
    ///
    /// OpenRouter routing deliberately does NOT key on the adapter's
    /// name heuristics: a discovered OpenRouter model id such as
    /// `anthropic/claude-sonnet-4-5` would be misread as native
    /// Anthropic, and routing on the name alone could silently move a
    /// native model to OpenRouter billing. The order is: (1) the
    /// discovery record for this exact model id — authoritative when
    /// present, and a non-OpenRouter record vetoes the SDK path;
    /// (2) the persisted provider selection (set by the Settings
    /// provider sections); (3) the adapter specification as a last
    /// resort. Bare ids without "/" are never OpenRouter ids (native
    /// Anthropic ids carry no slash), so they return nil immediately.
    public static func applicableKind(for selectedModel: String) -> SDKSessionKind? {
        if OpenCodeModelID.isOpenCodeModelID(selectedModel) {
            return .openCode
        }
        guard selectedModel.contains("/") else { return nil }
        if let discovered = AssistModelDiscoveryService.shared.discoveredModels.first(where: { $0.modelIdentifier == selectedModel }) {
            return discovered.providerID == "openrouter" ? .openRouter : nil
        }
        if AssistProviderSelection.persistedProvider == .openRouter {
            return .openRouter
        }
        let specification = AgentModelAdapter.shared.specification(for: selectedModel)
        if specification.provider == .openRouter {
            return .openRouter
        }
        return nil
    }

    /// Maps the persisted tool-source setting to an OpenCode run
    /// source, or nil when the combination is unsupported (openrouter
    /// tools do not exist for OpenCode sessions). Nil is an explicit
    /// rejection, never a silent substitution.
    public static func openCodeToolSource(for setting: SDKToolSourceSetting) -> OpenCodeSDKToolSource? {
        switch setting {
        case .swiftcode: return .swiftcode
        case .opencode: return .opencode
        case .combined: return .combined
        case .openrouter: return nil
        }
    }

    /// Maps the persisted tool-source setting to an OpenRouter run
    /// source, or nil when the combination is unsupported (opencode
    /// tools do not exist for OpenRouter sessions).
    public static func openRouterToolSource(for setting: SDKToolSourceSetting) -> OpenRouterSDKToolSource? {
        switch setting {
        case .swiftcode: return .swiftcode
        case .openrouter: return .openrouter
        case .combined: return .combined
        case .opencode: return nil
        }
    }

    public func cancel() async {
        await activeOpenCode?.cancel()
        await activeOpenRouter?.cancel()
        activeOpenCode = nil
        activeOpenRouter = nil
    }

    /// Runs one SDK session and returns the model's final text. Tool
    /// events are published to the store as the run proceeds; the caller
    /// (AssistAgentSession) owns posting the final text to the transcript.
    public func run(
        kind: SDKSessionKind,
        objective: String,
        context: AssistContext
    ) async throws -> String {
        let systemPrompt = try AssistManager.shared.getSystemPrompt()
        let history = Self.historyItems()
        let tools = Self.toolDefinitions()
        let toolSource = SDKToolSourceSetting.load()
        let sessionKey = context.sessionId.uuidString

        switch kind {
        case .openCode:
            guard let openCodeSource = Self.openCodeToolSource(for: toolSource) else {
                throw SDKSessionRunnerError.unsupportedToolSource(provider: "OpenCode", source: toolSource.rawValue)
            }
            let scriptPath = try Self.ensureBridgeScript(provider: .openCode, fileName: "opencode-bridge.mjs")
            let provider = OpenCodeSDKProvider(scriptPath: scriptPath)
            activeOpenCode = provider
            defer { activeOpenCode = nil }
            let request = OpenCodeSDKRunRequest(
                model: AssistModelManager.shared.selectedModelID,
                systemPrompt: systemPrompt,
                userText: objective,
                history: history.map { OpenCodeSDKHistoryItem(role: $0.role, text: $0.text) },
                tools: tools.map { OpenCodeSDKToolDefinition(name: $0.name, description: $0.description, parametersJSON: $0.parametersJSON) },
                toolSource: openCodeSource,
                directory: context.workspaceRoot.path
            )
            let stream = await provider.run(
                request,
                onToolEvent: Self.storeEventHandler(sessionKey: sessionKey),
                executeTool: { _, name, arguments in
                    try await Self.executeNativeTool(name: name, argumentsJSON: arguments, context: context)
                }
            )
            var finalText = ""
            for try await delta in stream {
                finalText += delta
            }
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SDKSessionRunnerError.emptyFinalResponse
            }
            return finalText
        case .openRouter:
            guard let openRouterSource = Self.openRouterToolSource(for: toolSource) else {
                throw SDKSessionRunnerError.unsupportedToolSource(provider: "OpenRouter", source: toolSource.rawValue)
            }
            let scriptPath = try Self.ensureBridgeScript(provider: .openRouter, fileName: "openrouter-bridge.mjs")
            let provider = OpenRouterSDKProvider(scriptPath: scriptPath)
            activeOpenRouter = provider
            defer { activeOpenRouter = nil }
            let request = OpenRouterSDKRunRequest(
                model: AssistModelManager.shared.selectedModelID,
                systemPrompt: systemPrompt,
                userText: objective,
                history: history.map { OpenRouterSDKHistoryItem(role: $0.role, text: $0.text) },
                tools: tools.map { OpenRouterSDKToolDefinition(name: $0.name, description: $0.description, parametersJSON: $0.parametersJSON) },
                toolSource: openRouterSource
            )
            let stream = await provider.run(
                request,
                onToolEvent: Self.storeEventHandler(sessionKey: sessionKey),
                executeTool: { _, name, arguments in
                    try await Self.executeNativeTool(name: name, argumentsJSON: arguments, context: context)
                }
            )
            var finalText = ""
            for try await delta in stream {
                finalText += delta
            }
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SDKSessionRunnerError.emptyFinalResponse
            }
            return finalText
        }
    }

    // MARK: - Bridge installation

    /// Verifies the pinned SDK is installed and the bridge script is in
    /// place under the runtime directory (where ESM imports resolve).
    /// Install state is revalidated from disk on every call — never
    /// trusted from a previous launch — and nothing is installed
    /// implicitly here: installation happens explicitly in Settings.
    private static func ensureBridgeScript(provider: SDKProvider, fileName: String) throws -> String {
        let installed = SDKRuntimeManager.installedVersion(for: provider)
        guard installed == provider.pinnedVersion else {
            throw SDKSessionRunnerError.runtimeNotInstalled(provider: provider, expected: provider.pinnedVersion)
        }
        guard let bridgeDir = SDKRuntimeManager.bridgeDirectory(for: provider) else {
            throw SDKSessionRunnerError.runtimeNotInstalled(provider: provider, expected: provider.pinnedVersion)
        }
        let installedURL = bridgeDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: installedURL.path) {
            return installedURL.path
        }
        let resourceName = (fileName as NSString).deletingPathExtension
        guard let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: "mjs"),
              let contents = try? String(contentsOf: bundleURL, encoding: .utf8) else {
            throw SDKSessionRunnerError.bridgeScriptMissing(provider: provider, fileName: fileName)
        }
        let written = try SDKRuntimeManager.shared.writeBridgeScript(for: provider, fileName: fileName, contents: contents)
        return written.path
    }

    // MARK: - Request construction

    private struct HistoryItem {
        let role: String
        let text: String
    }

    private struct ToolDefinition {
        let name: String
        let description: String
        let parametersJSON: String
    }

    /// Last 20 non-notice transcript messages. System messages are
    /// skipped: the system prompt already carries SwiftCode's
    /// instructions, and re-injecting transcript system rows would
    /// duplicate them.
    private static func historyItems() -> [HistoryItem] {
        AssistManager.shared.messages.suffix(20).compactMap { message in
            guard message.noticeLevel == nil, !message.content.isEmpty else { return nil }
            switch message.role {
            case .assistant: return HistoryItem(role: "assistant", text: message.content)
            case .user: return HistoryItem(role: "user", text: message.content)
            case .system: return nil
            }
        }
    }

    /// Every registered, non-disabled tool schema. Disabled tools are
    /// never offered to a model; availability is re-checked at execution
    /// time by registry validation, so a tool disabled mid-run still
    /// fails closed.
    private static func toolDefinitions() -> [ToolDefinition] {
        let registry = AssistToolRegistry.shared
        return registry.getToolSchemas().compactMap { schema in
            guard let name = schema["name"] as? String,
                  let description = schema["description"] as? String else { return nil }
            if let health = registry.getHealth(name), health.status == .disabled {
                return nil
            }
            var parametersJSON = "{}"
            if let parameters = schema["parameters"],
               let data = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) {
                parametersJSON = text
            }
            return ToolDefinition(name: name, description: description, parametersJSON: parametersJSON)
        }
    }

    // MARK: - Tool events

    /// Re-keys bridge events to the Assist session id (bridges report
    /// their own server/request session ids) and publishes them to the
    /// store. The closure itself is non-isolated and Sendable: it
    /// captures only the session key and hops to the MainActor store.
    private static func storeEventHandler(sessionKey: String) -> @Sendable (SDKToolEvent) -> Void {
        { event in
            let rekeyed = SDKToolEvent(
                id: event.id,
                provider: event.provider,
                sessionId: sessionKey,
                toolCallId: event.toolCallId,
                toolName: event.toolName,
                toolDescription: event.toolDescription,
                source: event.source,
                state: event.state,
                arguments: event.arguments,
                result: event.result,
                error: event.error,
                startedAt: event.startedAt,
                completedAt: event.completedAt
            )
            Task { @MainActor in
                SDKToolEventStore.shared.apply(rekeyed)
            }
        }
    }

    // MARK: - Native tool execution

    /// Executes one SwiftCode-native tool call through the registry.
    /// Validation (registration, disabled/unavailable, required args,
    /// types, path traversal) runs first; the corrected input from
    /// validation is what executes. A failed validation, unknown tool,
    /// or unsuccessful result throws — the bridge reports it to the
    /// model as a tool error, never as a success.
    private static func executeNativeTool(
        name: String,
        argumentsJSON: String,
        context: AssistContext
    ) async throws -> String {
        let registry = AssistToolRegistry.shared
        guard let data = argumentsJSON.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "AssistSDKSessionRunner", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Tool \"\(name)\" received malformed JSON arguments; nothing was executed."]
            )
        }
        let validation = registry.validate(toolId: name, arguments: arguments)
        guard validation.isValid else {
            throw NSError(
                domain: "AssistSDKSessionRunner", code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Tool \"\(name)\" failed validation: \(validation.issue ?? "invalid arguments"). Nothing was executed."]
            )
        }
        let effectiveId = registry.resolve(toolId: name)?.id ?? name
        guard let tool = registry.getTool(effectiveId) else {
            throw NSError(
                domain: "AssistSDKSessionRunner", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Tool \"\(name)\" is not registered. Nothing was executed."]
            )
        }
        let result = try await tool.execute(input: validation.correctedInput ?? arguments, context: context)
        guard result.success else {
            throw NSError(
                domain: "AssistSDKSessionRunner", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Tool \"\(tool.id)\" failed: \(result.error ?? result.output)"]
            )
        }
        return AssistToolResultFormatter.modelFacingPayload(toolId: tool.id, result: result)
    }
}
