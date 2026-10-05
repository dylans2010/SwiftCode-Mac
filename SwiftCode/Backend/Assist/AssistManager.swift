import Foundation
import Combine

@MainActor
public final class AssistManager: ObservableObject {
    public static let shared = AssistManager()

    @Published public var messages: [AssistMessage] = []
    @Published public var isProcessing = false
    @Published public var lastError: String?
    @Published public var takeoverReason: String?
    @Published public var currentCodeReview: CodeReviewInternalResult?
    @Published public var isCodeReviewRunning: Bool = false
    @Published public var hasCodeReviewBeenInvoked: Bool = false
    @Published public var queuedMessages: [QueuedAssistMessage] = []
    @Published public var currentActivityStatus: String = "Idle"

    // Thinking Progress & Duration State
    @Published public var activeThinkingText: String = ""
    @Published public var isThinking: Bool = false
    @Published public var thinkingStartedAt: Date? = nil
    @Published public var thinkingDurationSeconds: Int = 0
    private var thinkingTimerTask: Task<Void, Never>?

    public func startThinkingTimer() {
        if thinkingTimerTask == nil {
            thinkingStartedAt = Date()
            thinkingDurationSeconds = 0
            thinkingTimerTask = Task { @MainActor [weak self] in
                while let self = self, self.isThinking {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled || !self.isThinking { break }
                    if let start = self.thinkingStartedAt {
                        self.thinkingDurationSeconds = max(1, Int(Date().timeIntervalSince(start)))
                        self.currentActivityStatus = "Thinking (\(self.thinkingDurationSeconds)s)..."
                        if let idx = self.messages.indices.last {
                            self.messages[idx].thinkingDuration = Double(self.thinkingDurationSeconds)
                        }
                    }
                }
            }
        }
    }

    public func stopThinkingTimer() {
        thinkingTimerTask?.cancel()
        thinkingTimerTask = nil
        isThinking = false
    }

    public let logger = AssistLogger()
    public let session = AssistSession()
    public let agentSession = AssistAgentSession()
    public let registry = AssistToolRegistry()
    private let permissions = AssistPermissionsManager()
    private let memory = AssistMemoryGraph()

    private var agent: AssistAgent?
    private let api = AssistAPI.shared
    private var activeAgentTask: Task<Void, Never>?
    private var activeGoogleCloudSession: GoogleCloudSDKSession?
    private var activeGoogleCloudTask: Task<Void, Never>?
    private var activeGoogleCloudModelId: String?
    private var activeGoogleCloudModelDisplayName: String?

    // Transcript vs Model Context separation
    public private(set) var modelContext: [ModelContextSection] = []
    public private(set) var contextPressure: ContextPressureState?
    private var contextEngine: AssistContextEngine?

    // Cache for bundled system prompt
    private var cachedSystemPrompt: String?

    // Terminal Approval state variables
    @Published public var pendingTerminalRequest: TerminalApprovalRequest?
    public var terminalContinuation: CheckedContinuation<Bool, Never>?
    @Published public var terminalLiveOutput: String = ""
    @Published public var terminalRunning: Bool = false
    @Published public var terminalExitCode: Int? = nil
    @Published public var terminalCompleted: Bool = false
    @Published public var activeProcess: Process?
    @Published public var activeFallbackMessage: String?

    public func getSystemPrompt() throws -> String {
        if let cached = cachedSystemPrompt {
            return cached
        }

        guard let url = Bundle.main.url(forResource: "AgentSystemAsset", withExtension: "md") else {
            let errorMsg = "Failed to locate AgentSystemAsset.md in application bundle."
            Task { await logger.error(errorMsg, toolId: nil) }
            throw NSError(domain: "AssistManager", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        do {
            let prompt = try String(contentsOf: url, encoding: .utf8)
            cachedSystemPrompt = prompt
            return prompt
        } catch {
            let errorMsg = "Failed to load AgentSystemAsset.md from bundle: \(error.localizedDescription)"
            Task { await logger.error(errorMsg, toolId: nil) }
            throw NSError(domain: "AssistManager", code: 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
    }

    @MainActor
    public func requestTerminalApproval(_ request: TerminalApprovalRequest) async -> Bool {
        self.pendingTerminalRequest = request
        self.terminalLiveOutput = ""
        self.terminalRunning = false
        self.terminalExitCode = nil
        self.terminalCompleted = false

        return await withCheckedContinuation { continuation in
            self.terminalContinuation = continuation
        }
    }

    @MainActor
    public func approveTerminalRequest() {
        guard let continuation = terminalContinuation else { return }
        terminalContinuation = nil
        self.terminalRunning = true
        continuation.resume(returning: true)
    }

    @MainActor
    public func denyTerminalRequest() {
        guard let continuation = terminalContinuation else { return }
        terminalContinuation = nil
        self.pendingTerminalRequest = nil
        continuation.resume(returning: false)
    }

    @MainActor
    public func cancelTerminalExecution() {
        if let process = activeProcess, process.isRunning {
            process.terminate()
            appendTerminalOutput("\n[Execution cancelled by user]")
        }
        if let continuation = terminalContinuation {
            terminalContinuation = nil
            continuation.resume(returning: false)
        }
        self.pendingTerminalRequest = nil
        self.terminalRunning = false
        self.activeProcess = nil
    }

    @MainActor
    public func appendTerminalOutput(_ text: String) {
        self.terminalLiveOutput += text
    }

    public var selectedModel: AssistModelOption {
        let modelID = AssistModelManager.shared.selectedModelID
        if let match = AssistModelOption.all.first(where: { $0.id == modelID }) {
            return match
        }
        return AssistModelOption(
            id: modelID,
            displayName: modelID,
            provider: LLMService.shared.provider(for: modelID).rawValue
        )
    }

    private var selectedProvider: AssistModelProvider {
        let providerRawValue = UserDefaults.standard.string(forKey: "assist.selectedProvider") ?? AssistModelProvider.openAI.rawValue
        return AssistModelProvider(rawValue: providerRawValue) ?? .openAI
    }

    private init() {
        AssistExecutionFunctions.initializeRegistry()
        loadHistory()
        setupAgent()
        observeFallbackState()
    }

    private func setupAgent() {
        let context = buildContext()
        self.api.configure(context: context)
        self.agent = AssistAgent(context: context, registry: registry)
    }

    private func observeFallbackState() {
        Task { @MainActor in
            for await _ in AssistModelManager.shared.$lastFallbackMessage.values {
                if let message = AssistModelManager.shared.lastFallbackMessage {
                    activeFallbackMessage = message
                    messages.append(AssistMessage(role: .system, content: message))
                    saveHistory()
                }
            }
        }
    }

    private func buildContext() -> AssistContext {
        let builder = AssistContextBuilder(
            logger: logger,
            permissions: permissions,
            memory: memory,
            fileSystem: AssistFileSystem(workspaceRoot: ProjectSessionStore.shared.activeProject?.directoryURL ?? URL(fileURLWithPath: "/")),
            git: AssistGitManager(project: ProjectSessionStore.shared.activeProject)
        )
        return builder.buildContext(sessionId: session.id)
    }

    public func sendMessage(_ content: String, attachments: [AgentFileContext] = []) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If already processing, enqueue the message for sequential execution
        guard !isProcessing else {
            await MainActor.run {
                enqueueMessage(trimmed, attachments: attachments)
            }
            return
        }

        await MainActor.run {
            messages.append(AssistMessage(role: .user, content: trimmed, attachments: attachments))
            isProcessing = true
            isThinking = false
            activeThinkingText = ""
            thinkingStartedAt = nil
            thinkingDurationSeconds = 0
            currentActivityStatus = "Thinking..."
            lastError = nil
            saveHistory()
        }

        let isAgentMode = UserDefaults.standard.bool(forKey: "com.swiftcode.assist.mode")
        let isAntigravityAvailable = GoogleCloudSDKRuntime.shared.isAvailable

        // Always prioritize Antigravity in Agent Mode or when explicitly enabled
        if AppSettings.shared.isGoogleCloudAssist || (isAgentMode && isAntigravityAvailable) {
            await sendGoogleCloudSDKMessage(trimmed, attachments: attachments)
            return
        }

        if isAgentMode {
            guard let _ = self.agent else {
                let error = "Assist agent is unavailable."
                await MainActor.run {
                    lastError = error
                    messages.append(AssistMessage(role: .system, content: error))
                    isProcessing = false
                    saveHistory()
                }
                return
            }

            // Verify system prompt is available
            do {
                _ = try getSystemPrompt()
            } catch {
                await MainActor.run {
                    let errorMsg = "Runtime Configuration Error: The required system prompt 'AgentSystemAsset.md' could not be loaded: \(error.localizedDescription)"
                    lastError = errorMsg
                    messages.append(AssistMessage(role: .system, content: errorMsg))
                    isProcessing = false
                    saveHistory()
                }
                return
            }

            let context = buildContext()
            let task = Task {
                defer {
                    Task { @MainActor in
                        self.isProcessing = false
                        self.currentActivityStatus = "Idle"
                        self.processNextQueuedMessageIfAny()
                    }
                }
                do {
                    try await agentSession.start(objective: trimmed, attachments: attachments, context: context)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        messages.append(AssistMessage(role: .assistant, content: "Autonomous task execution finished."))
                        saveHistory()
                    }
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        lastError = "Agent execution failed: \(error.localizedDescription)"
                        messages.append(AssistMessage(role: .system, content: error.localizedDescription))
                        saveHistory()
                    }
                }
            }
            activeAgentTask = task
            _ = await task.result
            await MainActor.run {
                self.isProcessing = false
            }
            return
        }

        // Processing through Chat Mode: Query Model directly and conversationally (no tools/planning)
        do {
            // --- COMPREHENSIVE CHAT MODE STATE VALIDATION ---
            let selectedModel = AssistModelManager.shared.selectedModelID
            let selectedProvider = LLMService.shared.provider(for: selectedModel)

            await logger.info("[ChatMode] Validating session state. Model: \(selectedModel), Provider: \(selectedProvider.rawValue)")

            if selectedProvider != .offline && selectedProvider != .codex {
                let key = LLMService.shared.retrieveAPIKey(for: selectedProvider)
                guard !key.isEmpty else {
                    let errorMsg = "Chat Validation Failed: Missing API key / credentials for provider \(selectedProvider.rawValue). Please configure your key in Assist Settings."
                    await MainActor.run {
                        lastError = errorMsg
                        messages.append(AssistMessage(role: .system, content: errorMsg))
                        isProcessing = false
                        saveHistory()
                    }
                    return
                }
            } else if selectedProvider == .offline {
                guard FoundationModels.shared.isEnabled else {
                    let errorMsg = "Chat Validation Failed: Local Apple Foundation Models are selected but disabled. Please enable them in Assist Settings."
                    await MainActor.run {
                        lastError = errorMsg
                        messages.append(AssistMessage(role: .system, content: errorMsg))
                        isProcessing = false
                        saveHistory()
                    }
                    return
                }
            }
            // ------------------------------------------------

            let assetSystemPrompt = try getSystemPrompt()

            let context = buildContext()
            if contextEngine == nil {
                contextEngine = AssistContextEngine(context: context)
            }

            let messagesCopy = await MainActor.run { self.messages }
            let recentMessages = messagesCopy.suffix(15)

            let transcriptSection = ModelContextSection(
                priority: .p1,
                title: "Conversation History",
                content: recentMessages.map { msg in
                    let roleStr = msg.role == .user ? "User" : (msg.role == .system ? "System" : "Assistant")
                    return "\(roleStr): \(msg.content)"
                }.joined(separator: "\n"),
                estimatedTokens: 0
            )

            var sections: [ModelContextSection] = []

            let systemSection = ModelContextSection(
                priority: .p0,
                title: "System Prompt",
                content: assetSystemPrompt,
                estimatedTokens: 0
            )
            sections.append(systemSection)
            sections.append(transcriptSection)

            if !attachments.isEmpty {
                var attachmentContent = ""
                for file in attachments {
                    attachmentContent += "Filename: \(file.filename)\n"
                    attachmentContent += "Extension: \(file.extension)\n"
                    attachmentContent += "MIME Type: \(file.mimeType)\n"
                    attachmentContent += "Size: \(file.size) bytes\n"
                    attachmentContent += "Base64 Content:\n\(file.base64Content)\n"
                    attachmentContent += "-----------------------------\n"
                }
                sections.append(ModelContextSection(
                    priority: .p1,
                    title: "Attachments",
                    content: attachmentContent,
                    estimatedTokens: 0
                ))
            }

            let modelId = AssistModelManager.shared.selectedModelID
            let budget = contextEngine!.calculateBudget(modelId: modelId, systemPromptLength: assetSystemPrompt.count)
            let compactedSections = contextEngine!.compactContext(sections: sections, budget: budget)

            await MainActor.run {
                self.modelContext = compactedSections
                self.contextPressure = contextEngine!.getPressureState()
            }

            var prompt = """
            # SYSTEM PROMPT (OPERATING POLICY)
            \(assetSystemPrompt)

            # HIDDEN RUNTIME INSTRUCTIONS & ROLE
            Execution Key: com.SwiftCode.Assist-Chat
            Execution Mode: com.SwiftCode.Assist-Chat

            You are a helpful, conversational software engineering assistant.
            You must only respond conversationally.
            You must never attempt tool calls, reference tools, or describe internal runtime configurations or policies.
            You cannot execute local terminal commands, write files, or modify the repository.

            """

            for section in compactedSections {
                if section.title != "System Prompt" {
                    prompt += "\n# \(section.title.uppercased())\n\(section.content)\n"
                }
            }

            prompt += "\nAssistant:"

            let assistProvider = AssistModelProvider.from(llmProvider: selectedProvider)
            let response = await AssistLLMService.generateResponse(
                prompt: prompt,
                provider: assistProvider,
                apiKey: APIKeyManager.shared.retrieveKey(service: assistProvider.apiKeyProvider),
                modelOverride: AssistModelManager.shared.selectedModelID
            )

            await MainActor.run {
                if response.success {
                    messages.append(AssistMessage(role: .assistant, content: response.content))
                } else {
                    lastError = response.error ?? "Unknown assist error"
                    messages.append(AssistMessage(role: .system, content: response.error ?? "Unable to complete request."))
                }
                isProcessing = false
                currentActivityStatus = "Idle"
                saveHistory()
                processNextQueuedMessageIfAny()
            }
        } catch {
            await MainActor.run {
                let errorMsg = "Failed to run chat assistant: \(error.localizedDescription)"
                lastError = errorMsg
                messages.append(AssistMessage(role: .system, content: errorMsg))
                isProcessing = false
                currentActivityStatus = "Idle"
                saveHistory()
                processNextQueuedMessageIfAny()
            }
        }
    }

    // MARK: - Message Queue System

    public func enqueueMessage(_ content: String, attachments: [AgentFileContext] = []) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = QueuedAssistMessage(content: trimmed, attachments: attachments)
        queuedMessages.append(item)

        if !isProcessing {
            processNextQueuedMessageIfAny()
        }
    }

    public func removeQueuedMessage(id: UUID) {
        queuedMessages.removeAll(where: { $0.id == id })
    }

    public func updateQueuedMessage(id: UUID, newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeQueuedMessage(id: id)
            return
        }
        if let idx = queuedMessages.firstIndex(where: { $0.id == id }) {
            queuedMessages[idx].content = trimmed
        }
    }

    public func sendQueuedMessageNow(id: UUID) {
        guard let idx = queuedMessages.firstIndex(where: { $0.id == id }) else { return }
        let msg = queuedMessages.remove(at: idx)
        interruptActiveSessionAndSend(content: msg.content, attachments: msg.attachments)
    }

    public func interruptActiveSessionAndSend(content: String, attachments: [AgentFileContext] = []) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isProcessing {
            // Signal graceful turn cancellation to the bridge without tearing down the session or chat
            if let gcSession = activeGoogleCloudSession {
                Task {
                    try? await gcSession.cancel()
                }
            }
            activeAgentTask?.cancel()
            activeAgentTask = nil
            activeGoogleCloudTask?.cancel()
            activeGoogleCloudTask = nil
            WorkerRuntimeState.shared.stopAllActiveWorkers(reason: "Interrupted by user for continuation.")
            cancelTerminalExecution()
            stopThinkingTimer()

            // Finalize previous assistant message so its activity group is marked non-executing
            if let idx = messages.indices.last {
                messages[idx].activityGroup?.isExecuting = false
                saveHistory()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.isProcessing = false
            self.currentActivityStatus = "Idle"
            await self.sendMessage(trimmed, attachments: attachments)
        }
    }

    public func clearQueue() {
        queuedMessages.removeAll()
    }

    private var isDispatchingFromQueue: Bool = false

    public func processNextQueuedMessageIfAny() {
        guard !isProcessing, !isDispatchingFromQueue, !queuedMessages.isEmpty else { return }
        isDispatchingFromQueue = true
        let next = queuedMessages.removeFirst()
        Task { @MainActor in
            defer { self.isDispatchingFromQueue = false }
            await self.sendMessage(next.content, attachments: next.attachments)
        }
    }

    public func stopCurrentSession() {
        activeAgentTask?.cancel()
        activeAgentTask = nil

        activeGoogleCloudTask?.cancel()
        activeGoogleCloudTask = nil

        if let gcSession = activeGoogleCloudSession {
            Task {
                try? await gcSession.cancel()
            }
        }

        agentSession.cancel()

        WorkerRuntimeState.shared.stopAllActiveWorkers(reason: "Operation stopped by user.")
        PlanQuestionManager.shared.cancelPendingQuestions()
        cancelTerminalExecution()

        Task { @MainActor in
            self.stopThinkingTimer()
            self.isThinking = false
            self.isProcessing = false
            self.currentActivityStatus = "Cancelled"
            self.currentCodeReview = nil
            self.isCodeReviewRunning = false
            if let idx = self.messages.indices.last {
                if var activity = self.messages[idx].activityGroup {
                    for i in activity.tools.indices where activity.tools[i].status == .running {
                        activity.tools[i].status = .failed
                        activity.tools[i].result = "Cancelled"
                        let label = activity.tools[i].displayLabel ?? activity.tools[i].toolId
                        activity.tools[i].purpose = "\(label) (Cancelled)"
                    }
                    activity.isExecuting = false
                    self.messages[idx].activityGroup = activity
                }
            }
            self.saveHistory()
        }
    }

    public func clearChat() {
        // Immediately cancel the active agent task and agent session
        activeAgentTask?.cancel()
        activeAgentTask = nil

        activeGoogleCloudTask?.cancel()
        activeGoogleCloudTask = nil

        if let gcSession = activeGoogleCloudSession {
            let sessionToClose = gcSession
            activeGoogleCloudSession = nil
            Task {
                try? await sessionToClose.close()
            }
        }

        agentSession.cancel()

        // Clean up workers and pending questions
        WorkerRuntimeState.shared.stopAllActiveWorkers(reason: "Chat cleared by user.")
        WorkerRuntimeState.shared.clearAllWorkers()
        PlanQuestionManager.shared.cancelPendingQuestions()

        // Immediately cancel terminal execution and any running sub-processes
        cancelTerminalExecution()

        // Reset states to a clean, idle state
        isProcessing = false
        currentActivityStatus = "Idle"
        lastError = nil
        takeoverReason = nil
        currentCodeReview = nil
        isCodeReviewRunning = false
        hasCodeReviewBeenInvoked = false
        activeFallbackMessage = nil
        AssistModelManager.shared.clearFallbackNotification()

        messages.removeAll()
        clearQueue()
        session.reset()
        UserDefaults.standard.removeObject(forKey: "com.swiftcode.assist.history")
    }

    public func registerCapabilityExecution(_ text: String) {
        let systemMessage = AssistMessage(role: .system, content: text)
        messages.append(systemMessage)
        saveHistory()
    }

    public func rejectPlan() {
        session.currentPlan = nil
        registerCapabilityExecution("Plan rejected.")
    }

    public func applyPlan(_ plan: AssistExecutionPlan) async throws {
        guard var executingPlan = session.currentPlan ?? session.history.first(where: { $0.id == plan.id }) ?? Optional(plan) else {
            return
        }

        let response = await api.execute(plan: executingPlan)

        if response.success {
            executingPlan.status = .completed
            session.currentPlan = executingPlan
            if let index = session.history.firstIndex(where: { $0.id == executingPlan.id }) {
                session.history[index] = executingPlan
            } else {
                session.history.append(executingPlan)
            }
            registerCapabilityExecution("Plan applied successfully.")
        } else {
            registerCapabilityExecution("Failed to apply plan: \(response.error ?? "Unknown error")")
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.assist.history"),
           let history = try? JSONDecoder().decode([AssistMessage].self, from: data) {
            self.messages = history
        }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: "com.swiftcode.assist.history")
        }
    }

    // MARK: - Google Cloud SDK / Antigravity Execution Pipeline

    private func sendGoogleCloudSDKMessage(_ content: String, attachments: [AgentFileContext] = []) async {
        let runtime = GoogleCloudSDKRuntime.shared
        do {
            try await runtime.ensureStarted()
        } catch {
            await MainActor.run {
                self.lastError = "Google Antigravity engine failed to start: \(error.localizedDescription)"
                self.messages.append(AssistMessage(role: .system, content: "Engine error: \(error.localizedDescription)"))
                self.isProcessing = false
                self.saveHistory()
            }
            return
        }

        let sdkAttachments: [GoogleCloudSDKAttachment] = attachments.map {
            GoogleCloudSDKAttachment(name: $0.filename, path: $0.filename, mimeType: $0.mimeType, content: $0.base64Content)
        }

        let isSavedModels = AppSettings.shared.useSavedModels
        let initialRouted = isSavedModels ? AssistModelRouter.shared.selectModelForSDK() : nil
        let initialConfig = initialRouted?.config ?? GoogleCloudSDKConfiguration.resolveDefault()
        let initialModelId = initialRouted?.model.modelIdentifier ?? initialConfig.model
        let initialModelName = initialRouted?.model.displayName ?? (initialConfig.model)

        let session: GoogleCloudSDKSession
        if let existing = activeGoogleCloudSession {
            session = existing
        } else {
            do {
                session = try await runtime.createSession(config: initialConfig)
                activeGoogleCloudSession = session
                activeGoogleCloudModelId = initialModelId
                activeGoogleCloudModelDisplayName = initialModelName
            } catch {
                await MainActor.run {
                    self.lastError = "Failed to create Antigravity session: \(error.localizedDescription)"
                    self.messages.append(AssistMessage(role: .system, content: "Session error: \(error.localizedDescription)"))
                    self.isProcessing = false
                    self.saveHistory()
                }
                return
            }
        }

        let initialActivity = AssistActivityGroup(isExecuting: true)
        await MainActor.run {
            var initialMsg = AssistMessage(role: .assistant, content: "")
            initialMsg.activityGroup = initialActivity
            self.messages.append(initialMsg)
            self.saveHistory()
        }

        let task = Task {
            defer {
                Task { @MainActor in
                    self.stopThinkingTimer()
                    self.isProcessing = false
                    self.currentActivityStatus = "Idle"
                }
            }

            var currentPrompt = content
            var currentAttachments = sdkAttachments
            var currentSession: GoogleCloudSDKSession = session
            var currentConfig = initialConfig
            var currentModelId = initialModelId
            var currentModelName = initialModelName
            var attempts = 0
            let maxFailoverAttempts = 15

            executionLoop: while attempts < maxFailoverAttempts {
                attempts += 1
                let eventStream = await currentSession.subscribeEvents()
                var turnError: String? = nil
                var turnCompletedSuccessfully = false

                let streamTask = Task { @MainActor in
                    streamLoop: for await event in eventStream {
                        guard !Task.isCancelled else { break streamLoop }
                        guard let idx = self.messages.indices.last else { continue }
                        switch event {
                        case .agentProgress(_, let delta, let thoughtDelta):
                            if let thought = thoughtDelta, !thought.isEmpty {
                                if !self.isThinking {
                                    self.isThinking = true
                                    self.startThinkingTimer()
                                }
                                self.activeThinkingText += thought
                                self.messages[idx].thinkingContent = self.activeThinkingText
                            }
                            if let delta = delta {
                                if self.isThinking {
                                    self.stopThinkingTimer()
                                    if let start = self.thinkingStartedAt {
                                        self.thinkingDurationSeconds = max(1, Int(Date().timeIntervalSince(start)))
                                        self.messages[idx].thinkingDuration = Double(self.thinkingDurationSeconds)
                                    }
                                }
                                self.currentActivityStatus = "Responding..."
                                self.messages[idx] = AssistMessage(
                                    role: self.messages[idx].role,
                                    content: self.messages[idx].content + delta,
                                    attachments: self.messages[idx].attachments,
                                    mcpExecution: self.messages[idx].mcpExecution,
                                    composioExecution: self.messages[idx].composioExecution,
                                    activityGroup: self.messages[idx].activityGroup,
                                    thinkingContent: self.messages[idx].thinkingContent,
                                    thinkingDuration: self.messages[idx].thinkingDuration
                                )
                            }
                        case .toolStarted(let tool):
                            let argsDict: [String: Any] = (try? JSONSerialization.jsonObject(with: tool.rawArgs.data(using: .utf8) ?? Data())) as? [String: Any] ?? [:]
                            self.reportToolStarted(callId: tool.id, toolName: tool.name, arguments: argsDict)

                        case .toolCompleted(let res):
                            self.reportToolCompleted(callId: res.id, toolName: res.name, output: res.result, arguments: [:])

                        case .toolFailed(let toolId, let name, let err):
                            self.reportToolFailed(callId: toolId, toolName: name, error: err, arguments: [:])

                        case .workerStarted(_, let workerId, let name, let args):
                            self.reportWorkerStarted(workerId: workerId, name: name, args: args)

                        case .workerProgress(_, _, let progress):
                            self.currentActivityStatus = progress

                        case .workerCompleted(_, let workerId, let result):
                            self.reportWorkerCompleted(workerId: workerId, result: result)

                        case .workerFailed(_, let workerId, let error):
                            self.reportWorkerFailed(workerId: workerId, error: error)

                        case .agentCompleted(_, let response, _, _):
                            self.stopThinkingTimer()
                            if let start = self.thinkingStartedAt {
                                self.messages[idx].thinkingDuration = Double(max(1, Int(Date().timeIntervalSince(start))))
                            }
                            self.thinkingStartedAt = nil
                            self.activeThinkingText = ""

                            if var activity = self.messages[idx].activityGroup {
                                for tIdx in activity.tools.indices where activity.tools[tIdx].status == .running {
                                    activity.tools[tIdx].status = .completed
                                    if let comp = activity.tools[tIdx].completedLabel {
                                        activity.tools[tIdx].purpose = comp
                                    }
                                }
                                activity.isExecuting = false
                                self.messages[idx].activityGroup = activity
                            }

                            let currentContent = self.messages[idx].content
                            let finalContent = currentContent.isEmpty ? response : currentContent
                            self.messages[idx] = AssistMessage(
                                role: self.messages[idx].role,
                                content: finalContent,
                                attachments: self.messages[idx].attachments,
                                mcpExecution: self.messages[idx].mcpExecution,
                                composioExecution: self.messages[idx].composioExecution,
                                activityGroup: self.messages[idx].activityGroup,
                                thinkingContent: self.messages[idx].thinkingContent,
                                thinkingDuration: self.messages[idx].thinkingDuration
                            )
                            self.messages[idx].activityGroup?.isExecuting = false
                            self.saveHistory()
                            self.currentActivityStatus = "Idle"
                            self.isProcessing = false
                            turnCompletedSuccessfully = true
                            break streamLoop

                        case .agentFailed(_, let err):
                            self.stopThinkingTimer()
                            self.thinkingStartedAt = nil
                            self.activeThinkingText = ""
                            turnError = err

                            if var activity = self.messages[idx].activityGroup {
                                for tIdx in activity.tools.indices where activity.tools[tIdx].status == .running {
                                    activity.tools[tIdx].status = .failed
                                    activity.tools[tIdx].result = err
                                }
                                self.messages[idx].activityGroup = activity
                            }
                            break streamLoop

                        default:
                            break
                        }
                    }
                }

                do {
                    try await currentSession.sendMessage(currentPrompt, attachments: currentAttachments)
                    _ = await streamTask.result
                } catch {
                    streamTask.cancel()
                    turnError = error.localizedDescription
                }

                if turnCompletedSuccessfully {
                    break executionLoop
                }

                let altKeysEnabled = await MainActor.run { AppSettings.shared.alternativeKeysEnabled }
                let savedModelsEnabled = await MainActor.run { AppSettings.shared.useSavedModels }
                let isGemini = currentModelId.lowercased().contains("gemini") || currentModelName.lowercased().contains("gemini") || (currentConfig.provider == nil || currentConfig.provider == "gemini" || currentConfig.provider == "google")

                if let errText = turnError {
                    let isQuota = AssistModelRouter.shared.isQuotaOrRateLimit(errorText: errText)
                    let isPermanentAuth = errText.contains("401") || errText.contains("403") || errText.contains("API_KEY_INVALID") || errText.contains("invalid api key")

                    // 1. Alternative Keys Rotation (Gemini)
                    if altKeysEnabled && isGemini && (isQuota || isPermanentAuth) {
                        let activeId = await MainActor.run { AlternativeKeyManager.shared.activeKeyId }

                        if isPermanentAuth, let aid = activeId {
                            await MainActor.run {
                                AlternativeKeyManager.shared.markFailed(id: aid, isPermanentAuthError: true)
                            }
                        } else if isQuota {
                            if let aid = activeId {
                                await MainActor.run {
                                    AlternativeKeyManager.shared.markRateLimited(id: aid, retryAfterSeconds: 60.0)
                                }
                            }

                            // Update activity UI exactly per specification:
                            // "Gemini key rate limited — rotating key"
                            await MainActor.run {
                                self.currentActivityStatus = "Gemini key rate limited — rotating key"
                            }

                            // "Waiting 2 seconds before retry"
                            await MainActor.run {
                                self.currentActivityStatus = "Waiting 2 seconds before retry"
                            }
                            // Mandatory 2-second backend wait
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                        }

                        // Select next available key
                        let nextKeyResult = await MainActor.run {
                            AlternativeKeyManager.shared.selectNextAvailableKey(excludingId: activeId)
                        }

                        if let nextKey = nextKeyResult {
                            let keyIndex = nextKey.metadata.orderIndex + 1
                            await MainActor.run {
                                self.currentActivityStatus = "Switched to Gemini key \(keyIndex)"
                                if let idx = self.messages.indices.last {
                                    // Clear aborted buffer so retry writes cleanly into current assistant message
                                    self.messages[idx].content = ""
                                    self.messages[idx].thinkingContent = ""
                                    self.messages[idx].activityGroup?.isExecuting = true
                                }
                            }

                            // Cleanly close previous session
                            await runtime.closeSession(id: currentSession.id)
                            await MainActor.run {
                                self.activeGoogleCloudSession = nil
                            }

                            currentConfig.apiKey = nextKey.key
                            do {
                                let newSession = try await runtime.createSession(config: currentConfig)
                                await MainActor.run {
                                    self.activeGoogleCloudSession = newSession
                                }
                                currentSession = newSession
                                continue executionLoop
                            } catch {
                                turnError = error.localizedDescription
                                continue executionLoop
                            }
                        } else {
                            // All Gemini keys exhausted
                            if !savedModelsEnabled {
                                await MainActor.run {
                                    self.lastError = "All configured Gemini API keys are currently unavailable."
                                    if let idx = self.messages.indices.last {
                                        self.messages[idx].activityGroup?.isExecuting = false
                                        self.messages[idx] = AssistMessage(
                                            role: .assistant,
                                            content: "All configured Gemini API keys are currently unavailable."
                                        )
                                    }
                                    self.saveHistory()
                                    self.currentActivityStatus = "Idle"
                                    self.isProcessing = false
                                }
                                break executionLoop
                            }
                        }
                    }

                    // 2. Saved Models Multi-Provider Fallover
                    if savedModelsEnabled {
                        let priorOutput = await MainActor.run { self.messages.last?.content ?? "" }
                        if let failover = await AssistModelRouter.shared.handleTurnFailure(
                            failedModelIdentifier: currentModelId,
                            errorText: errText,
                            originalPrompt: content,
                            priorTurnOutput: priorOutput
                        ) {
                            let oldName = currentModelName
                            let newName = failover.nextModel.displayName
                            await MainActor.run {
                                self.currentActivityStatus = "\(oldName) quota reached — switching to \(newName)"
                                if let idx = self.messages.indices.last {
                                    self.messages[idx].activityGroup?.isExecuting = true
                                }
                            }

                            // Cleanly close previous session
                            await runtime.closeSession(id: currentSession.id)
                            await MainActor.run {
                                self.activeGoogleCloudSession = nil
                            }

                            // Create session with failover candidate
                            do {
                                let newSession = try await runtime.createSession(config: failover.nextConfig)
                                await MainActor.run {
                                    self.activeGoogleCloudSession = newSession
                                    self.activeGoogleCloudModelId = failover.nextModel.modelIdentifier
                                    self.activeGoogleCloudModelDisplayName = newName
                                }
                                currentSession = newSession
                                currentConfig = failover.nextConfig
                                currentModelId = failover.nextModel.modelIdentifier
                                currentModelName = newName
                                currentPrompt = failover.continuationPrompt
                                currentAttachments = []
                                continue executionLoop
                            } catch {
                                turnError = error.localizedDescription
                                currentModelId = failover.nextModel.modelIdentifier
                                continue executionLoop
                            }
                        }
                    }
                }

                // Terminal failure
                await MainActor.run {
                    let finalErrorMsg = (altKeysEnabled && isGemini) ? "All configured Gemini API keys are currently unavailable." : (turnError ?? "Execution failed")
                    self.lastError = finalErrorMsg
                    if let idx = self.messages.indices.last {
                        self.messages[idx].activityGroup?.isExecuting = false
                        if self.messages[idx].content.isEmpty {
                            self.messages[idx] = AssistMessage(role: .assistant, content: finalErrorMsg)
                        }
                    }
                    self.saveHistory()
                    self.currentActivityStatus = "Idle"
                    self.isProcessing = false
                }
                break executionLoop
            }
        }

        activeGoogleCloudTask = task
        _ = await task.result
        await MainActor.run {
            self.isProcessing = false
            self.currentActivityStatus = "Idle"
            self.processNextQueuedMessageIfAny()
        }
    }

    // MARK: - Live Tool & Activity Reporting

    @MainActor
    public func reportToolStarted(callId: String, toolName: String, arguments: [String: Any]) {
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        self.currentActivityStatus = formatted.runningLabel
        self.stopThinkingTimer()
        self.isThinking = false

        guard let idx = self.messages.indices.last else { return }
        var activity = self.messages[idx].activityGroup ?? AssistActivityGroup(isExecuting: true)
        activity.isExecuting = true

        let itemId = UUID(uuidString: callId) ?? UUID()
        if let existingIdx = activity.tools.firstIndex(where: { $0.id == itemId || ($0.toolId == toolName && $0.status == .running) }) {
            activity.tools[existingIdx].status = .running
            activity.tools[existingIdx].purpose = formatted.runningLabel
            activity.tools[existingIdx].displayLabel = formatted.runningLabel
            activity.tools[existingIdx].completedLabel = formatted.completedLabel
            activity.tools[existingIdx].iconName = formatted.iconName
        } else {
            let newItem = ToolActivityItem(
                id: itemId,
                toolId: toolName,
                purpose: formatted.runningLabel,
                result: "",
                status: .running,
                duration: 0.0,
                timestamp: Date(),
                displayLabel: formatted.runningLabel,
                completedLabel: formatted.completedLabel,
                iconName: formatted.iconName
            )
            activity.tools.append(newItem)
        }

        // File operations integration
        if let path = AssistToolActivityFormatter.extractFilePath(arguments: arguments) {
            let op = AssistToolActivityFormatter.determineFileOperation(toolId: toolName)
            if let op = op {
                if !activity.files.contains(where: { $0.filePath == path }) {
                    activity.files.append(FileActivityItem(filePath: path, operation: op))
                }
            }
        }

        // Build operations integration
        if toolName == "project_build" || toolName == "build_project" || toolName == "build" {
            if !activity.builds.contains(where: { $0.status == .running }) {
                activity.builds.append(BuildActivityItem(scheme: "SwiftCode", status: .running))
            }
        }

        // Test operations integration
        if toolName == "run_tests" || toolName == "test_runner" || toolName == "test" {
            if !activity.tests.contains(where: { $0.status == .running }) {
                activity.tests.append(TestActivityItem(suiteName: "SwiftCodeTests", status: .running))
            }
        }

        // Terminal operations integration
        if toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command" {
            let rawCmd = arguments["command"] as? String ?? arguments["CommandLine"] as? String ?? arguments["cmd"] as? String ?? ""
            if !rawCmd.isEmpty && !activity.terminalCommands.contains(where: { $0.command == rawCmd }) {
                activity.terminalCommands.append(TerminalActivityItem(command: rawCmd, workingDirectory: ProjectSessionStore.shared.activeProject?.directoryURL.path ?? "", output: "", exitCode: 0, status: .running, timestamp: Date()))
            }
        }

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportToolCompleted(callId: String, toolName: String, output: String?, arguments: [String: Any]) {
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        self.currentActivityStatus = formatted.completedLabel

        guard let idx = self.messages.indices.last else { return }
        guard var activity = self.messages[idx].activityGroup else { return }

        let itemId = UUID(uuidString: callId)
        let toolIdx = activity.tools.firstIndex(where: {
            (itemId != nil && $0.id == itemId) || ($0.toolId == toolName && $0.status == .running)
        })

        if let tIdx = toolIdx {
            activity.tools[tIdx].status = .completed
            activity.tools[tIdx].result = output ?? ""
            activity.tools[tIdx].duration = max(0.1, Date().timeIntervalSince(activity.tools[tIdx].timestamp))
            activity.tools[tIdx].purpose = formatted.completedLabel
            activity.tools[tIdx].completedLabel = formatted.completedLabel
        } else {
            let newItem = ToolActivityItem(
                id: itemId ?? UUID(),
                toolId: toolName,
                purpose: formatted.completedLabel,
                result: output ?? "",
                status: .completed,
                duration: 0.1,
                timestamp: Date(),
                displayLabel: formatted.runningLabel,
                completedLabel: formatted.completedLabel,
                iconName: formatted.iconName
            )
            activity.tools.append(newItem)
        }

        // Finalize builds
        if toolName == "project_build" || toolName == "build_project" || toolName == "build" {
            for bIdx in activity.builds.indices where activity.builds[bIdx].status == .running {
                activity.builds[bIdx].status = .completed
                activity.builds[bIdx].duration = Date().timeIntervalSince(activity.builds[bIdx].timestamp)
            }
        }

        // Finalize tests
        if toolName == "run_tests" || toolName == "test_runner" || toolName == "test" {
            for tIdx in activity.tests.indices where activity.tests[tIdx].status == .running {
                activity.tests[tIdx].status = .completed
                activity.tests[tIdx].passedCount = max(1, activity.tests[tIdx].passedCount)
                activity.tests[tIdx].duration = Date().timeIntervalSince(activity.tests[tIdx].timestamp)
            }
        }

        // Finalize terminal
        if toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command" {
            for cIdx in activity.terminalCommands.indices where activity.terminalCommands[cIdx].status == .running {
                activity.terminalCommands[cIdx].status = .completed
                activity.terminalCommands[cIdx].output = output ?? ""
            }
        }

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportToolFailed(callId: String, toolName: String, error: String, arguments: [String: Any]) {
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        self.currentActivityStatus = formatted.failedLabel

        guard let idx = self.messages.indices.last else { return }
        guard var activity = self.messages[idx].activityGroup else { return }

        let itemId = UUID(uuidString: callId)
        let toolIdx = activity.tools.firstIndex(where: {
            (itemId != nil && $0.id == itemId) || ($0.toolId == toolName && $0.status == .running)
        })

        if let tIdx = toolIdx {
            activity.tools[tIdx].status = .failed
            activity.tools[tIdx].result = error
            activity.tools[tIdx].duration = max(0.1, Date().timeIntervalSince(activity.tools[tIdx].timestamp))
            activity.tools[tIdx].purpose = formatted.failedLabel
        } else {
            let newItem = ToolActivityItem(
                id: itemId ?? UUID(),
                toolId: toolName,
                purpose: formatted.failedLabel,
                result: error,
                status: .failed,
                duration: 0.1,
                timestamp: Date(),
                displayLabel: formatted.runningLabel,
                completedLabel: formatted.completedLabel,
                iconName: formatted.iconName
            )
            activity.tools.append(newItem)
        }

        // Finalize builds
        if toolName == "project_build" || toolName == "build_project" || toolName == "build" {
            for bIdx in activity.builds.indices where activity.builds[bIdx].status == .running {
                activity.builds[bIdx].status = .failed
                activity.builds[bIdx].errorCount = 1
                activity.builds[bIdx].duration = Date().timeIntervalSince(activity.builds[bIdx].timestamp)
            }
        }

        // Finalize tests
        if toolName == "run_tests" || toolName == "test_runner" || toolName == "test" {
            for tIdx in activity.tests.indices where activity.tests[tIdx].status == .running {
                activity.tests[tIdx].status = .failed
                activity.tests[tIdx].failedCount = 1
                activity.tests[tIdx].duration = Date().timeIntervalSince(activity.tests[tIdx].timestamp)
            }
        }

        // Finalize terminal
        if toolName == "use_terminal" || toolName == "task_runner" || toolName == "run_command" {
            for cIdx in activity.terminalCommands.indices where activity.terminalCommands[cIdx].status == .running {
                activity.terminalCommands[cIdx].status = .failed
                activity.terminalCommands[cIdx].output = error
            }
        }

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportWorkerStarted(workerId: String, name: String, args: String) {
        self.currentActivityStatus = "Worker: \(name)..."
        guard let idx = self.messages.indices.last else { return }
        var activity = self.messages[idx].activityGroup ?? AssistActivityGroup(isExecuting: true)
        let item = WorkerActivityItem(
            workerId: workerId,
            name: name,
            role: "Subagent",
            scope: "Workspace",
            taskDescription: args,
            status: .running
        )
        activity.workers.append(item)
        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportWorkerCompleted(workerId: String, result: String) {
        self.currentActivityStatus = "Worker completed"
        guard let idx = self.messages.indices.last else { return }
        guard var activity = self.messages[idx].activityGroup else { return }
        if let wIdx = activity.workers.indices.last {
            activity.workers[wIdx].status = .completed
            activity.workers[wIdx].progress = 1.0
        }
        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportWorkerFailed(workerId: String, error: String) {
        self.currentActivityStatus = "Worker failed"
        guard let idx = self.messages.indices.last else { return }
        guard var activity = self.messages[idx].activityGroup else { return }
        if let wIdx = activity.workers.indices.last {
            activity.workers[wIdx].status = .failed
        }
        self.messages[idx].activityGroup = activity
    }
}
