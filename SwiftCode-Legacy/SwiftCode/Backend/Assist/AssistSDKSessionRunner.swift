import Foundation

public enum SDKSessionKind: Sendable {
    case openCode
    case openRouter
    case hermes
}

public enum SDKSessionRunnerError: LocalizedError, Sendable {
    case runtimeNotInstalled(provider: SDKProvider, expected: String)
    case bridgeScriptMissing(provider: SDKProvider, fileName: String)
    case unsupportedToolSource(provider: String, source: String)
    case emptyFinalResponse
    case hermesUsesHermesRunner

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
        case .hermesUsesHermesRunner:
            return "Hermes sessions run through HermesSessionRunner, not the SDK bridge. Reselect the model and retry."
        }
    }
}

@MainActor
public final class AssistSDKSessionRunner {
    private var activeOpenCode: OpenCodeSDKProvider?
    private var activeOpenRouter: OpenRouterSDKProvider?

    public init() {}

    public static func applicableKind(for selectedModel: String) -> SDKSessionKind? {
        if HermesModelID.isHermesModelID(selectedModel) {
            return nil
        }
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

    public static func openCodeToolSource(for setting: SDKToolSourceSetting) -> OpenCodeSDKToolSource? {
        switch setting {
        case .swiftcode: return .swiftcode
        case .opencode: return .opencode
        case .combined: return .combined
        case .openrouter: return nil
        }
    }

    public static func openRouterToolSource(for setting: SDKToolSourceSetting) -> OpenRouterSDKToolSource? {
        switch setting {
        case .swiftcode: return .swiftcode
        case .openrouter: return .openrouter
        case .combined: return .combined
        case .opencode: return nil
        }
    }

    private var lastSessionKey: String?

    public func cancel() async {
        await activeOpenCode?.cancel()
        await activeOpenRouter?.cancel()
        activeOpenCode = nil
        activeOpenRouter = nil
        if let sessionKey = lastSessionKey {
            SDKToolEventStore.shared.cancelNonTerminal(sessionId: sessionKey)
        }
    }

    public func run(
        kind: SDKSessionKind,
        objective: String,
        context: AssistContext
    ) async throws -> String {
        let systemPrompt = try await Self.buildSystemPrompt(objective: objective)
        let history = Self.historyItems(objective: objective)
        let tools = Self.toolDefinitions()
        let toolSource = SDKToolSourceSetting.effective()
        let sessionKey = context.sessionId.uuidString
        lastSessionKey = sessionKey

        switch kind {
        case .openCode:
            guard let openCodeSource = Self.openCodeToolSource(for: toolSource) else {
                throw SDKSessionRunnerError.unsupportedToolSource(provider: "OpenCode", source: toolSource.rawValue)
            }
            let scriptPath = try await Self.ensureBridgeScript(provider: .openCode, fileName: "opencode-bridge.mjs")
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
            let scriptPath = try await Self.ensureBridgeScript(provider: .openRouter, fileName: "openrouter-bridge.mjs")
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
        case .hermes:
            throw SDKSessionRunnerError.hermesUsesHermesRunner
        }
    }

    public static func buildSystemPrompt(objective: String) async throws -> String {
        AssistManager.shared.invalidateSystemPromptCache()
        let baselinePrompt = try AssistManager.shared.getSystemPrompt()
        let instructionQuery = InstructionQueryContext(
            userText: objective,
            taskCategory: SystemIndexService.classifyCategory(for: objective),
            stage: .preparation,
            modelID: AssistModelManager.shared.selectedModelID,
            maxTokens: 4000,
            excludingChunkIDs: AssistManager.shared.activeRetrievalLedger?.retrievedChunkIDs ?? []
        )
        let instructionRetrieval = await SystemIndexService.shared.retrieve(for: instructionQuery)
        AssistManager.shared.recordRetrieval(instructionRetrieval)
        let retrievedBlock = instructionRetrieval.formattedForPrompt()
        return retrievedBlock.isEmpty
            ? baselinePrompt
            : "\(baselinePrompt)\n\n\(retrievedBlock)"
    }

    private static func ensureBridgeScript(provider: SDKProvider, fileName: String) async throws -> String {
        let installed = SDKRuntimeManager.installedVersion(for: provider)
        guard installed == provider.pinnedVersion else {
            throw SDKSessionRunnerError.runtimeNotInstalled(provider: provider, expected: provider.pinnedVersion)
        }
        guard let bridgeDir = SDKRuntimeManager.bridgeDirectory(for: provider) else {
            throw SDKSessionRunnerError.runtimeNotInstalled(provider: provider, expected: provider.pinnedVersion)
        }
        let installedURL = bridgeDir.appendingPathComponent(fileName)
        let resourceName = (fileName as NSString).deletingPathExtension
        let bundleContents = Bundle.main.url(forResource: resourceName, withExtension: "mjs")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        if FileManager.default.fileExists(atPath: installedURL.path) {
            if let bundleContents,
               let installedContents = try? String(contentsOf: installedURL, encoding: .utf8),
               installedContents == bundleContents {
                return installedURL.path
            }
            if bundleContents == nil {
                return installedURL.path
            }
        }
        guard let contents = bundleContents else {
            throw SDKSessionRunnerError.bridgeScriptMissing(provider: provider, fileName: fileName)
        }
        let written = try await SDKRuntimeManager.shared.writeBridgeScript(for: provider, fileName: fileName, contents: contents)
        return written.path
    }

    private struct HistoryItem {
        let role: String
        let text: String
    }

    private struct ToolDefinition {
        let name: String
        let description: String
        let parametersJSON: String
    }

    private static func historyItems(objective: String) -> [HistoryItem] {
        var items = AssistManager.shared.messages.suffix(20).compactMap { message -> HistoryItem? in
            guard message.noticeLevel == nil, !message.content.isEmpty else { return nil }
            switch message.role {
            case .assistant:
                if message.content.contains("identify the relevant files before making any changes") {
                    return nil
                }
                return HistoryItem(role: "assistant", text: message.content)
            case .user: return HistoryItem(role: "user", text: message.content)
            case .system: return nil
            }
        }
        if let last = items.last, last.role == "user", last.text == objective {
            items.removeLast()
        }
        return items
    }

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
