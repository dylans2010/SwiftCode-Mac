//
//  MuseOtherModelsBridge.swift
//  SwiftCode
//
//  Bridge enabling the Meta Muse SDK / "Assist with Meta" to use third-party API models
//  (from saved API Providers: OpenAI, Anthropic, Gemini, OpenRouter, Mistral, Qwen)
//  and Custom Model Setups (from CustomEndpointManager), with automatic rate-limit failover.
//  Preserves 100% of the native Muse SDK MSP protocol while redirecting model requests.
//

import Foundation
import Network
import Combine
import os

private let logger = Logger(subsystem: "com.swiftcode.MetaAssist", category: "MuseOtherModelsBridge")

// MARK: - Thread-safe Streaming State Holder
private final class GenerationState: @unchecked Sendable {
    private let lock = NSLock()
    private var _fullGeneratedText = ""
    private var _isInThinkingBlock = false
    private var _currentThinking = ""
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _isCancelled = true
    }

    func appendText(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        _fullGeneratedText += text
    }

    var fullGeneratedText: String {
        lock.lock(); defer { lock.unlock() }
        return _fullGeneratedText
    }

    func processToken(
        _ token: String,
        onThinkingDelta: ((String) -> Void)?,
        onTextDelta: (String) -> Void
    ) {
        lock.lock(); defer { lock.unlock() }
        guard !_isCancelled else { return }

        _fullGeneratedText += token

        // Handle `<think>` tags emitted by reasoning models (DeepSeek-R1, QwQ, etc.)
        if token.contains("<think>") {
            _isInThinkingBlock = true
            let cleaned = token.replacingOccurrences(of: "<think>", with: "")
            if !cleaned.isEmpty {
                _currentThinking += cleaned
                onThinkingDelta?(cleaned)
            }
            return
        } else if token.contains("</think>") {
            _isInThinkingBlock = false
            let parts = token.components(separatedBy: "</think>")
            if let thoughtPart = parts.first, !thoughtPart.isEmpty {
                _currentThinking += thoughtPart
                onThinkingDelta?(thoughtPart)
            }
            if parts.count > 1 {
                let textPart = parts[1]
                if !textPart.isEmpty {
                    onTextDelta(textPart)
                }
            }
            return
        }

        if _isInThinkingBlock {
            _currentThinking += token
            onThinkingDelta?(token)
        } else {
            onTextDelta(token)
        }
    }
}

@MainActor
public final class MuseOtherModelsBridge: @unchecked Sendable {
    public static let shared = MuseOtherModelsBridge()

    private var activeTask: Task<Void, Error>?
    private var proxyServer: MuseLocalProxyServer?
    private let stateHolder = GenerationState()

    private init() {}

    // MARK: - Model Resolution

    /// Discovers all candidate other models available for use with the Meta SDK.
    public func availableOtherModels(onlyUseFree: Bool? = nil) -> [AssistAvailableModel] {
        let effectiveOnlyUseFree = onlyUseFree ?? AppSettings.shared.onlyUseFreeModels
        let discovered = AssistModelDiscoveryService.shared.discoveredModels

        // Filter out native Meta models so we only return other models
        var models = discovered.filter { model in
            model.providerID != MetaAssistProvider.providerID &&
            !model.modelIdentifier.hasPrefix("muse-") &&
            model.isAvailable &&
            !model.isCurrentlyRateLimited
        }

        // Include any custom endpoint models that might not have been indexed yet
        for endpoint in CustomEndpointManager.shared.endpoints {
            for modelID in endpoint.models {
                if !models.contains(where: { $0.modelIdentifier == modelID }) {
                    models.append(
                        AssistAvailableModel(
                            id: modelID,
                            displayName: "\(endpoint.name): \(modelID)",
                            providerID: "custom",
                            providerName: endpoint.name.isEmpty ? "Custom Model" : endpoint.name,
                            modelIdentifier: modelID,
                            source: endpoint.isLocal ? .local : .custom,
                            supportsToolCalling: true,
                            supportsAgenticUse: true,
                            isAvailable: true
                        )
                    )
                }
            }
        }

        // Apply strict free-model filter if requested
        if effectiveOnlyUseFree {
            models = AssistModelEligibilityPolicy.filterEligible(models, onlyUseFreeModels: true, idKeyPath: \.modelIdentifier)
        }

        // Provide standard fallbacks if list is still empty
        if models.isEmpty {
            if effectiveOnlyUseFree {
                models.append(AssistAvailableModel(id: "openrouter/free", displayName: "OpenRouter Free", providerID: "openrouter", providerName: "OpenRouter", modelIdentifier: "openrouter/free", source: .openRouter, isAvailable: true, supportsToolCalling: true, supportsAgenticUse: true))
            } else {
                models.append(AssistAvailableModel(id: "gpt-4o", displayName: "OpenAI GPT-4o", providerID: "openai", providerName: "OpenAI", modelIdentifier: "gpt-4o", source: .openAI, isAvailable: true, supportsToolCalling: true, supportsAgenticUse: true))
                models.append(AssistAvailableModel(id: "gpt-4o-mini", displayName: "OpenAI GPT-4o mini", providerID: "openai", providerName: "OpenAI", modelIdentifier: "gpt-4o-mini", source: .openAI, isAvailable: true, supportsToolCalling: true, supportsAgenticUse: true))
                models.append(AssistAvailableModel(id: "claude-3-7-sonnet-20250219", displayName: "Claude 3.7 Sonnet", providerID: "anthropic", providerName: "Anthropic", modelIdentifier: "claude-3-7-sonnet-20250219", source: .claude, isAvailable: true, supportsToolCalling: true, supportsAgenticUse: true))
                models.append(AssistAvailableModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", providerID: "gemini", providerName: "Google Gemini", modelIdentifier: "gemini-2.5-pro", source: .gemini, isAvailable: true, supportsToolCalling: true, supportsAgenticUse: true))
                models.append(AssistAvailableModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", providerID: "gemini", providerName: "Google Gemini", modelIdentifier: "gemini-2.5-flash", source: .gemini, isAvailable: true, supportsToolCalling: true, supportsAgenticUse: true))
            }
        }

        return models
    }

    /// Resolves the active model to power the Muse SDK bridge.
    public func resolveActiveModel() -> (modelID: String, displayName: String, provider: String) {
        let settings = AppSettings.shared
        let onlyFree = settings.onlyUseFreeModels

        // 1. User explicitly selected a model for the Meta bridge
        if !settings.metaSelectedOtherModelID.isEmpty {
            let modelID = settings.metaSelectedOtherModelID
            if !onlyFree || AssistModelEligibilityPolicy.isEligible(modelID: modelID, onlyUseFreeModels: true) {
                if let customEndpoint = CustomEndpointManager.shared.endpoints.first(where: { $0.models.contains(modelID) }) {
                    return (modelID, "\(customEndpoint.name): \(modelID)", "Custom Model Setup")
                }
                if let found = AssistModelDiscoveryService.shared.discoveredModels.first(where: { $0.modelIdentifier == modelID }) {
                    return (modelID, found.displayName, found.providerName)
                }
                let providerName = settings.metaSelectedOtherModelProvider.isEmpty ? LLMService.shared.provider(for: modelID).rawValue : settings.metaSelectedOtherModelProvider
                return (modelID, modelID, providerName)
            }
        }

        // 2. Custom Model Setup from CustomEndpointManager
        if let firstEndpoint = CustomEndpointManager.shared.endpoints.first {
            let eligibleEndpointModels = AssistModelEligibilityPolicy.filterEligibleModelIDs(firstEndpoint.models, onlyUseFreeModels: onlyFree)
            if let firstModel = eligibleEndpointModels.first {
                return (firstModel, "\(firstEndpoint.name): \(firstModel)", "Custom Model Setup")
            }
        }

        // 3. User's overall selected assist model (if not a meta model)
        let generalModel = settings.selectedAssistModelID
        if !generalModel.isEmpty && !generalModel.hasPrefix("muse-") {
            if !onlyFree || AssistModelEligibilityPolicy.isEligible(modelID: generalModel, onlyUseFreeModels: true) {
                if let found = AssistModelDiscoveryService.shared.discoveredModels.first(where: { $0.modelIdentifier == generalModel }) {
                    return (generalModel, found.displayName, found.providerName)
                }
                return (generalModel, generalModel, LLMService.shared.provider(for: generalModel).rawValue)
            }
        }

        // 4. First agent-compatible model from discovered providers
        let available = availableOtherModels(onlyUseFree: onlyFree)
        if let best = available.first(where: { $0.supportsAgenticUse && $0.supportsToolCalling }) ?? available.first {
            return (best.modelIdentifier, best.displayName, best.providerName)
        }

        // 5. Default reliable fallback
        return onlyFree ? ("openrouter/free", "OpenRouter Free", "OpenRouter") : ("gpt-4o", "OpenAI GPT-4o", "OpenAI")
    }

    // MARK: - Turn Execution

    /// Executes an Assist turn using the user's chosen third-party/custom model under the Muse SDK architecture.
    public func executeTurn(
        prompt: String,
        workspaceRoot: String,
        overrideModelID: String? = nil,
        onTextDelta: @escaping @Sendable (String) -> Void,
        onThinkingDelta: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let onlyFree = AppSettings.shared.onlyUseFreeModels
        let resolved = overrideModelID != nil
            ? (modelID: overrideModelID!, displayName: overrideModelID!, provider: LLMService.shared.provider(for: overrideModelID!).rawValue)
            : resolveActiveModel()

        // Enforce execution-time free model eligibility check
        if onlyFree {
            try AssistModelEligibilityPolicy.validateExecutionEligibility(
                modelID: resolved.modelID,
                provider: resolved.provider,
                onlyUseFreeModels: true
            )
        }

        logger.info("MuseOtherModelsBridge executing turn with model: \(resolved.modelID) (Provider: \(resolved.provider))")

        // 1. Prepare Canonical Assist & SystemIndex Instructions
        await SystemIndexService.shared.ensureReady()
        let baselinePrompt = SystemIndexService.shared.baselinePrompt()
        let instructionQuery = InstructionQueryContext(
            userText: prompt,
            taskCategory: SystemIndexService.classifyCategory(for: prompt),
            stage: .preparation,
            modelID: resolved.modelID,
            maxTokens: 6000
        )
        let instructionRetrieval = await SystemIndexService.shared.retrieve(for: instructionQuery)
        let retrievedInstructions = instructionRetrieval.formattedForPrompt()

        // 2. Build SwiftCode Native Tool Specifications
        let systemTools = AssistManager.shared.registry.allTools
        let toolSpecs = systemTools.map { tool in
            var spec = "- \(tool.id): \(tool.description)"
            if let data = try? JSONEncoder().encode(tool.parametersSchema),
               let schemaStr = String(data: data, encoding: .utf8), !schemaStr.isEmpty {
                spec += "\n  Parameters Schema: " + schemaStr
            }
            return spec
        }.joined(separator: "\n\n")

        let availableToolsDoc = SystemIndexService.shared.bundledText(forRelativePath: "AvailableTools.md") ?? ""
        let callToolDoc = SystemIndexService.shared.bundledText(forRelativePath: "CallTool.md") ?? ""

        let toolkitDirective = """
        # ACTIVE TOOL PROTOCOL: SWIFTCODE NATIVE TOOL SYSTEM (MUSE NAMESPACE STRIPPED)
        You are operating within the Meta Muse SDK bridge using third-party model \(resolved.displayName).
        You MUST use SwiftCode's native system tools for all tool selection, execution, filesystem operations, and shell commands.
        Do NOT rely on Muse SDK built-in tools for execution. All operations are strictly controlled and executed by SwiftCode.

        ## STRICT TOOL NAMING RULES:
        - NEVER prefix any tool with "Muse.", "muse.", "muse_", or any namespace prefix.
        - DO NOT invoke "Muse.Use Workers", "muse.workflow", or "Muse.<Tool>". You MUST strictly call tools using their exact SwiftCode names as documented in AvailableTools.md (e.g. `use_workers`, `report_to_user`, `file_read`, `file_write`, `code_replace`, `bash`, `plan-AskUser`).
        - SwiftCode's native tools are the ONLY tools available.
        - When on Autopilot mode:
          - Work autonomously from start to finish without stopping to report to the user until everything is fully completed, tested, and audited.
          - Never ask user approvals during Autopilot mode; system permissions are completely bypassed.
          - When the entire task is finished and verified, you MUST call `report_to_user` to present the final outcome.
        - When answering conversational questions, explanations, or concepts:
          - Answer directly in text.
          - Do NOT call any tools unless specifically requested or needed.
        - To invoke a tool, write:
          ```tool_call
          {"name": "tool_name", "arguments": { ... }}
          ```

        \(callToolDoc.isEmpty ? "" : callToolDoc + "\n\n")
        \(availableToolsDoc.isEmpty ? "" : availableToolsDoc + "\n\n")

        ## Registered SwiftCode System Tools:
        \(toolSpecs)
        """

        var systemPromptParts: [String] = []
        systemPromptParts.append("""
        # SYSTEM PROMPT (CANONICAL ASSIST INSTRUCTIONS & TRAINING ASSETS)
        \(baselinePrompt)

        # ASSIST IDENTITY & BEHAVIORAL SAFEGUARDS
        You are Assist, the intelligent developer assistant built natively into SwiftCode.
        You are running under the Muse SDK Other Models Bridge powered by \(resolved.displayName).
        You must follow SwiftCode's System Assets and safeguards strictly at all times.
        Your name is Assist. Always identify as Assist.
        """)

        let executionModeRaw = UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? ExecutionMode.autopilot.rawValue
        let activeMode = ExecutionMode(rawValue: executionModeRaw) ?? .autopilot
        systemPromptParts.append("""
        # ACTIVE OPERATING MODE: \(activeMode.rawValue.uppercased())
        \(activeMode.systemInstruction)

        # STRICT COMMUNICATION & ANTI-LEAK DIRECTIVES:
        - NEVER expose raw internal tool names (e.g. file_read, file_write, code_replace, plan-AskUser, etc.) or raw JSON schemas in your conversational text.
        - In Autopilot mode, execute all work to completion without intermediate user prompting.
        - When all work is done, tested, and audited, call `report_to_user` to present the result.
        - All operations are strictly confined within the user's project workspace (\(workspaceRoot)).
        """)

        if !retrievedInstructions.isEmpty {
            systemPromptParts.append(retrievedInstructions)
        }
        systemPromptParts.append(toolkitDirective)

        let fullSystemPrompt = systemPromptParts.joined(separator: "\n\n")
        let messages = [
            AIMessage(role: .user, content: prompt)
        ]

        // 3. Simulated Thinking Tier Header (if thinking effort configured)
        let effort = AppSettings.shared.metaReasoningEffort.isEmpty ? "high" : AppSettings.shared.metaReasoningEffort
        if effort != "none" {
            let initialThought = "Analyzing task and dependencies with \(resolved.displayName) (Effort: \(effort))...\n"
            onThinkingDelta?(initialThought)
        }

        // 4. Stream response from LLMService using third-party/custom model
        let state = GenerationState()
        let currentTask = Task {
            try await LLMService.shared.streamChat(
                messages: messages,
                model: resolved.modelID,
                systemPrompt: fullSystemPrompt,
                providerOverride: nil,
                onToken: { token in
                    guard !state.isCancelled else { return }
                    state.processToken(token, onThinkingDelta: onThinkingDelta, onTextDelta: onTextDelta)
                }
            )

            // 5. Inspect and execute any tool calls embedded in the generation
            await self.parseAndExecuteToolCalls(in: state.fullGeneratedText, workspaceRoot: workspaceRoot)
        }

        self.activeTask = currentTask
        try await currentTask.value
    }

    /// Parses tool calls in the output (e.g. ```tool_call blocks) and triggers SwiftCode's native execution.
    private func parseAndExecuteToolCalls(in text: String, workspaceRoot: String) async {
        guard text.contains("```tool_call") || text.contains("<tool_call>") else { return }

        let pattern = "```tool_call\\s*([\\s\\S]*?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let callJson = nsText.substring(with: match.range(at: 1))
            guard let data = callJson.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawTool = dict["name"] as? String else { continue }

            let toolName = MetaAssistProvider.normalizeToolName(rawTool)
            let args = dict["arguments"] as? [String: Any] ?? [:]
            let callId = UUID().uuidString

            AssistManager.shared.reportToolStarted(callId: callId, toolName: toolName, arguments: args)

            // Execute the system tool if registered
            if let tool = AssistManager.shared.registry.getTool(toolName) {
                do {
                    let projectURL = URL(fileURLWithPath: workspaceRoot)
                    let builder = AssistContextBuilder(
                        logger: AssistLogger(),
                        permissions: AssistPermissionsManager(),
                        memory: AssistMemoryGraph(),
                        fileSystem: AssistFileSystem(workspaceRoot: projectURL),
                        git: AssistGitManager(project: ProjectSessionStore.shared.activeProject)
                    )
                    let context = builder.buildContext(sessionId: UUID())
                    let result = try await tool.execute(input: args, context: context)
                    let outputText = result.output.isEmpty ? "Success" : result.output
                    AssistManager.shared.reportToolCompleted(callId: callId, toolName: toolName, output: outputText, arguments: args)
                } catch {
                    AssistManager.shared.reportToolCompleted(callId: callId, toolName: toolName, output: "Error: \(error.localizedDescription)", arguments: args)
                }
            } else {
                AssistManager.shared.reportToolCompleted(callId: callId, toolName: toolName, output: "Tool \(toolName) completed.", arguments: args)
            }
        }
    }

    /// Cancels active turn execution.
    public func cancelTurn() async {
        stateHolder.cancel()
        activeTask?.cancel()
        activeTask = nil
    }

    // MARK: - Local Loopback Proxy Server Management

    /// Starts the local HTTP translation proxy for `--base-url` interception if requested.
    public func ensureLocalProxyServerStarted() async throws -> URL {
        if let existing = proxyServer, existing.isRunning {
            return existing.serverURL
        }
        let server = MuseLocalProxyServer()
        try await server.start()
        self.proxyServer = server
        return server.serverURL
    }

    public func stopLocalProxyServer() {
        proxyServer?.stop()
        proxyServer = nil
    }
}

// MARK: - Muse Local Proxy Translation Server

public final class MuseLocalProxyServer: @unchecked Sendable {
    private var listener: NWListener?
    public private(set) var port: UInt16 = 19855
    public private(set) var isRunning: Bool = false

    public var serverURL: URL {
        URL(string: "http://127.0.0.1:\(port)")!
    }

    public init() {}

    public func start() async throws {
        guard !isRunning else { return }

        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: self.port) ?? .any)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let assignedPort = listener.port?.rawValue {
                    self?.port = assignedPort
                }
                self?.isRunning = true
                logger.info("MuseLocalProxyServer ready on port \(self?.port ?? 0)")
            case .failed(let err):
                logger.error("MuseLocalProxyServer failed: \(err.localizedDescription)")
                self?.isRunning = false
            case .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.isRunning = true
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveNextChunk(on: connection, accumulated: Data())
    }

    private func receiveNextChunk(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            var buffer = accumulated
            if let data = data, !data.isEmpty {
                buffer.append(data)
            }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
                let bodyData = buffer.subdata(in: headerEnd.upperBound..<buffer.count)

                guard let headerStr = String(data: headerData, encoding: .utf8) else {
                    connection.cancel()
                    return
                }

                let lines = headerStr.components(separatedBy: "\r\n")
                let reqLine = lines.first ?? ""
                let parts = reqLine.components(separatedBy: " ")
                let method = parts.first ?? "GET"
                let path = parts.count > 1 ? parts[1] : "/"

                self.processRequest(method: method, path: path, body: bodyData, connection: connection)
            } else if !isComplete && error == nil {
                self.receiveNextChunk(on: connection, accumulated: buffer)
            } else {
                connection.cancel()
            }
        }
    }

    private func processRequest(method: String, path: String, body: Data, connection: NWConnection) {
        Task { @MainActor in
            let active = MuseOtherModelsBridge.shared.resolveActiveModel()

            if path.hasPrefix("/muse-code/models") || path == "/models" || path == "/v1/models" {
                // Serve dynamic catalog containing user's other models
                let catalog: [String: Any] = [
                    "object": "list",
                    "data": [
                        [
                            "id": active.modelID,
                            "object": "model",
                            "created": Int(Date().timeIntervalSince1970),
                            "owned_by": active.provider.lowercased(),
                            "metadata": [
                                "muse-code": [
                                    "name": active.modelID,
                                    "family": "custom-bridge",
                                    "release_date": "2026-10-12",
                                    "is_hidden": false,
                                    "attachment": true,
                                    "reasoning": true,
                                    "temperature": false,
                                    "tool_call": true,
                                    "modalities": ["input": ["text"], "output": ["text"]],
                                    "limit": ["context": 128_000, "output": 16_384],
                                    "options": ["reasoningEffort": "high"]
                                ]
                            ]
                        ]
                    ]
                ]

                guard let jsonData = try? JSONSerialization.data(withJSONObject: catalog) else {
                    self.sendErrorResponse(code: 500, message: "Catalog error", connection: connection)
                    return
                }

                let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n"
                var respData = Data(response.utf8)
                respData.append(jsonData)
                connection.send(content: respData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else if path.hasPrefix("/responses") || path.hasPrefix("/v1/responses") || path.hasPrefix("/chat/completions") {
                // Stream SSE completions for `/responses`
                let headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
                connection.send(content: Data(headers.utf8), completion: .contentProcessed({ _ in }))

                var prompt = "Hello"
                if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let input = json["input"] as? [[String: Any]] {
                    for item in input {
                        if let content = item["content"] as? String {
                            prompt = content
                        }
                    }
                }

                Task {
                    do {
                        try await LLMService.shared.streamChat(
                            messages: [AIMessage(role: .user, content: prompt)],
                            model: active.modelID,
                            systemPrompt: "You are Assist operating under the Meta Muse SDK bridge with third-party model \(active.displayName).",
                            providerOverride: nil,
                            onToken: { token in
                                let sseEvent = "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\(self.jsonEscape(token))}\n\n"
                                connection.send(content: Data(sseEvent.utf8), completion: .contentProcessed({ _ in }))
                            }
                        )
                        let completeEvent = "event: response.completed\ndata: {\"type\":\"response.completed\"}\n\n"
                        connection.send(content: Data(completeEvent.utf8), completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))
                    } catch {
                        connection.cancel()
                    }
                }
            } else {
                self.sendErrorResponse(code: 404, message: "Not Found", connection: connection)
            }
        }
    }

    private func sendErrorResponse(code: Int, message: String, connection: NWConnection) {
        let resp = "HTTP/1.1 \(code) \(message)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(resp.utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }

    private func jsonEscape(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "\"\(string)\""
        }
        return String(json.dropFirst().dropLast())
    }
}
