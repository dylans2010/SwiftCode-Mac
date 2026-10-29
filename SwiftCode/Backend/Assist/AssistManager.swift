import Foundation
import Combine

@MainActor
public final class AssistManager: ObservableObject {
    public static let shared = AssistManager()

    @Published public var messages: [AssistMessage] = []
    @Published public var isProcessing = false
    @Published public var lastError: String? {
        didSet {
            // Capture error diagnostics at the single point every failure
            // path flows through: when the error occurred and which request
            // phase was active. Clearing the error clears its diagnostics.
            if lastError != nil {
                lastErrorDate = Date()
                lastErrorPhase = requestPhase
            } else {
                lastErrorDate = nil
                lastErrorPhase = nil
            }
        }
    }
    /// When `lastError` was recorded (nil when there is no error).
    @Published public private(set) var lastErrorDate: Date?
    /// The request phase active when `lastError` was recorded.
    @Published public private(set) var lastErrorPhase: AssistRequestPhase?
    /// Non-fatal warning for the current/last request (e.g. instruction
    /// content omitted by the context budget). Same diagnostics capture as
    /// errors; cleared on new requests and conversation reset.
    @Published public var lastWarning: String? {
        didSet {
            if lastWarning != nil {
                lastWarningDate = Date()
                lastWarningPhase = requestPhase
            } else {
                lastWarningDate = nil
                lastWarningPhase = nil
            }
        }
    }
    /// When `lastWarning` was recorded (nil when there is no warning).
    @Published public private(set) var lastWarningDate: Date?
    /// The request phase active when `lastWarning` was recorded.
    @Published public private(set) var lastWarningPhase: AssistRequestPhase?
    @Published public var takeoverReason: String?
    @Published public var currentCodeReview: CodeReviewInternalResult?
    @Published public var isCodeReviewRunning: Bool = false
    @Published public var hasCodeReviewBeenInvoked: Bool = false
    @Published public var queuedMessages: [QueuedAssistMessage] = []
    @Published public var currentActivityStatus: String = "Idle"
    /// Per-turn request metrics keyed by the assistant response message ID.
    /// Stored when a turn starts so the feedback package generator can attach
    /// checkpoint/latency telemetry to each assistant message. Cleared with
    /// the conversation in `clearChat()`.
    public var requestMetricsByMessageID: [UUID: AssistRequestMetrics] = [:]

    private var activeChatTask: Task<Void, Never>?

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
    private var activeMetaTask: Task<Void, Never>?

    // MARK: - Unified request lifecycle state (AssistRequestState.swift)
    //
    // `requestPhase` is the single source of truth for what the current
    // request is doing; `currentActivityStatus` is derived from it for UI
    // compatibility. `requestGenerationValue` invalidates late callbacks
    // after clearChat() or a newer request starts.
    private var requestGenerationValue: Int = 0
    public private(set) var requestPhase: AssistRequestPhase = .idle
    /// Request-scoped SystemIndex retrieval ledger. Cleared on conversation
    /// reset; the shared SystemIndex cache itself is never cleared here.
    public private(set) var activeRetrievalLedger: SystemIndexRequestLedger?

    /// Records a SystemIndex retrieval into the request-scoped ledger so
    /// later requests in the same conversation never re-inject the same
    /// chunks. Shared by the chat, Antigravity, and legacy agent paths.
    public func recordRetrieval(_ retrieval: SystemIndexBudgetResult) {
        var ledger = activeRetrievalLedger ?? SystemIndexRequestLedger()
        ledger.record(retrieval)
        activeRetrievalLedger = ledger
    }

    public func setRequestPhase(_ phase: AssistRequestPhase) {
        requestPhase = phase
        currentActivityStatus = phase.statusText
    }

    /// Centralized request failure used by early-return error paths.
    /// Records the error, moves to the terminal .failed phase, appends a
    /// system message, and stops processing — so the request phase can
    /// never be left stale on a failed request.
    private func failRequest(_ error: String, systemMessage: String? = nil) {
        lastError = error
        setRequestPhase(.failed)
        messages.append(AssistMessage(role: .system, content: systemMessage ?? error))
        isProcessing = false
        saveHistory()
    }

    /// Posts a warning/error as a first-class chat message — yellow for
    /// warnings, red for errors, tappable to expand, with an optional
    /// Server Error dialog carrying the raw API detail. The entry is also
    /// recorded in the log feed. This replaces bare logger.warning/error
    /// for user-facing events so nothing important only lives in the log.
    /// When `replacingPlaceholder` is true and the trailing message is the
    /// empty assistant "thinking" placeholder, it is replaced in place.
    public func postNotice(
        _ level: AssistNoticeLevel,
        _ message: String,
        serverError: ServerErrorDetail? = nil,
        replacingPlaceholder: Bool = false
    ) async {
        switch level {
        case .warning: await logger.warning(message)
        case .error: await logger.error(message)
        }
        await MainActor.run {
            var notice = AssistMessage(role: .system, content: message)
            notice.noticeLevel = level
            notice.serverError = serverError
            if replacingPlaceholder,
               let idx = self.messages.indices.last,
               self.messages[idx].role == .assistant,
               self.messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.messages[idx] = notice
            } else {
                self.messages.append(notice)
            }
            self.saveHistory()
        }
    }

    /// Shows the "Loading instructions…" phase only when the System Index
    /// genuinely isn't ready yet. The index is warmed at app launch, so
    /// retrieval is instant for any model once it's ready.
    private func beginInstructionRetrievalPhaseIfNeeded() async {
        if case .ready = await SystemIndexService.shared.status() {
            return
        }
        setRequestPhase(.retrievingInstructions)
    }

    private func nextGeneration() -> AssistRequestGeneration {
        requestGenerationValue += 1
        return AssistRequestGeneration(requestGenerationValue)
    }

    public var currentGeneration: AssistRequestGeneration {
        AssistRequestGeneration(requestGenerationValue)
    }

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

    /// Returns the baseline system prompt assembled from the canonical System
    /// Assets (AgentSystemAsset.md index + Identity.md + Safeguards.md).
    /// Task-specific instructions are retrieved separately per request via
    /// `SystemIndexService.retrieve(for:)` and injected by the request
    /// pipeline — this baseline is what every request carries.
    /// Drops the cached baseline prompt so the next getSystemPrompt()
    /// re-reads the current System Assets. The cache was previously
    /// never invalidated, so in-session asset updates never reached
    /// a later run within one app lifetime.
    public func invalidateSystemPromptCache() {
        cachedSystemPrompt = nil
    }

    public func getSystemPrompt() throws -> String {
        if let cached = cachedSystemPrompt {
            return cached
        }

        let prompt = SystemIndexService.shared.baselinePrompt()
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let errorMsg = "Failed to locate System Assets (AgentSystemAsset.md / Identity.md / Safeguards.md) in the application bundle."
            Task { await logger.error(errorMsg, toolId: nil) }
            throw NSError(domain: "AssistManager", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        cachedSystemPrompt = prompt
        return prompt
    }

    @MainActor
    public func requestTerminalApproval(_ request: TerminalApprovalRequest, timeoutSeconds: TimeInterval = 180.0) async -> Bool {
        self.pendingTerminalRequest = request
        self.terminalLiveOutput = ""
        self.terminalRunning = false
        self.terminalExitCode = nil
        self.terminalCompleted = false

        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            await MainActor.run {
                if self.pendingTerminalRequest?.id == request.id {
                    self.denyTerminalRequest()
                }
            }
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.terminalContinuation = continuation
        }

        timeoutTask.cancel()
        return result
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
        let activeRoot = ProjectSessionStore.shared.activeProject?.directoryURL ?? AssistContextBuilder.resolvedWorkspaceRoot()
        let builder = AssistContextBuilder(
            logger: logger,
            permissions: permissions,
            memory: memory,
            fileSystem: AssistFileSystem(workspaceRoot: activeRoot),
            git: AssistGitManager(project: ProjectSessionStore.shared.activeProject, workspaceRoot: activeRoot)
        )
        return builder.buildContext(sessionId: session.id)
    }

    /// N-1: pure decision contract for the Chat Mode Google credential check.
    /// A Google OAuth session satisfies the check only when the provider is
    /// Google, the auth mode is google_oauth, the session is authenticated,
    /// and a token was actually obtainable. The live fetch result is an
    /// explicit input so the contract is unit-testable.
    static func googleOAuthSatisfiesChatCheck(
        providerIsGoogle: Bool,
        authMode: String,
        isAuthenticated: Bool,
        tokenAvailable: Bool
    ) -> Bool {
        guard providerIsGoogle else { return false }
        guard authMode == "google_oauth", isAuthenticated else { return false }
        return tokenAvailable
    }

    public func sendMessage(
        _ content: String,
        attachments: [AgentFileContext] = [],
        envelope: AssistTaskEnvelope? = nil
    ) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If already processing, enqueue the message for sequential execution
        guard !isProcessing else {
            await MainActor.run {
                enqueueMessage(trimmed, attachments: attachments)
            }
            return
        }

        let metrics = AssistRequestMetrics.start(prompt: trimmed)
        // Generation token: clearChat() or a newer request invalidates this
        // generation, so late callbacks can never repopulate a cleared
        // conversation.
        let generation = nextGeneration()
        // Warm the shared instruction index off the critical path. Retrieval
        // calls below await it; the build is coalesced and cheap afterwards.
        Task.detached(priority: .utility) { await SystemIndexService.shared.ensureReady() }

        await MainActor.run {
            AssistEventNormalizer.shared.resetForNewTask()
            // Keep the submitted envelope on the stored message so
            // the history / AssistInfoView can show which command or
            // @Reverse invocation produced this turn. Previously the
            // envelope was dropped here (only forwarded to provider
            // paths), so the stored message lost the command context.
            messages.append(AssistMessage(role: .user, content: trimmed, attachments: attachments, envelope: envelope))
            isProcessing = true
            setRequestPhase(.preparingRequest)
            lastError = nil
            lastWarning = nil
            saveHistory()
        }

        metrics.mark(.sessionResolved)

        // SwiftCode Cloud Model: direct hosted-model path. Works under every
        // routing strategy with no API key or sign-in — the settings toggle is
        // the only gate. Takes precedence over the Antigravity session below.
        // Matches every cloud model ID ("swiftcode-cloud" and "swiftcode-cloud:<name>").
        if AppSettings.shared.useSwiftCodeCloudModel,
           SCCloudConfiguration.isCloudModelID(AppSettings.shared.selectedAssistModelID) {
            await sendSwiftCodeCloudMessage(trimmed, attachments: attachments, envelope: envelope, metrics: metrics)
            return
        }

        // "Use Provider Models" is on: never run a user-provided
        // model, and never substitute another one for it. Fail the
        // turn explicitly so the user picks a provider model in
        // Assist Settings instead of silently getting a different
        // model. SwiftCode Cloud models are provider-hosted, not
        // user-provided, and are handled by the short-circuit above.
        if AppSettings.shared.assistUseProviderModels {
            let selectedID = AppSettings.shared.selectedAssistModelID
            let discovered = AssistModelDiscoveryService.shared.discoveredModels.first(where: { $0.modelIdentifier == selectedID })
            if AssistModelRouter.isUserProvidedSelectedModelID(selectedID, discovered: discovered) {
                await MainActor.run {
                    failRequest("Use Provider Models is on, so Assist will not use the user-provided model '\(selectedID)'. Select a provider model in Assist Settings → Assist System → Provider Models.")
                }
                return
            }
        }

        // Assist with Meta (Muse Code SDK / MSP Protocol execution path)
        let selectedModelID = AppSettings.shared.selectedAssistModelID
        let selectedDiscoveredModel = AssistModelDiscoveryService.shared.discoveredModels.first(where: { $0.modelIdentifier == selectedModelID })
        let isMetaAssist = AppSettings.shared.isMetaAssist ||
            selectedDiscoveredModel?.providerID == MetaAssistProvider.providerID ||
            (selectedModelID == MetaAssistProvider.defaultModelID && selectedDiscoveredModel == nil)
        if isMetaAssist {
            await sendMetaAssistMessage(trimmed, attachments: attachments, envelope: envelope, metrics: metrics, generation: generation)
            return
        }

        let isAgentMode = UserDefaults.standard.bool(forKey: "com.swiftcode.assist.mode")
        let isLightweightConversation = attachments.isEmpty && envelope == nil && Self.isLightweightConversation(trimmed)
        let isAntigravityAvailable = GoogleCloudSDKRuntime.shared.isAvailable
        let googleAuthMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode
        let isGoogleOAuthSession = (googleAuthMode == "google_oauth") && GoogleAccountAuthService.shared.isAuthenticated && !AppSettings.shared.alternativeKeysEnabled

        // Always route through the Antigravity SDK runtime when Google Cloud Assist,
        // Agent Mode, or a Google Sign-In Antigravity session is active (including
        // lightweight greetings so they never bypass Antigravity and hit raw provider HTTP).
        if isAntigravityAvailable && (AppSettings.shared.isGoogleCloudAssist || isAgentMode || isGoogleOAuthSession) {
            await sendGoogleCloudSDKMessage(trimmed, attachments: attachments, envelope: envelope, metrics: metrics, generation: generation)
            return
        }

        if isAgentMode && !isLightweightConversation {
            guard let _ = self.agent else {
                let error = "Assist agent is unavailable."
                await MainActor.run {
                    failRequest(error)
                }
                return
            }

            // Verify system prompt is available
            do {
                _ = try getSystemPrompt()
            } catch {
                await MainActor.run {
                    failRequest("Runtime Configuration Error: The required system prompt 'AgentSystemAsset.md' could not be loaded: \(error.localizedDescription)")
                }
                return
            }

            let context = buildContext()
            let task = Task {
                defer {
                    Task { @MainActor in
                        // Only the current generation may reset shared UI
                        // state; a superseded generation must not resurrect
                        // "Idle" over a newer in-flight request. Never
                        // overwrite a terminal phase (e.g. cancelled).
                        guard generation == self.currentGeneration else { return }
                        self.isProcessing = false
                        if !self.requestPhase.isTerminal {
                            self.setRequestPhase(.idle)
                        }
                        self.processNextQueuedMessageIfAny()
                    }
                }
                do {
                    try await agentSession.start(objective: trimmed, attachments: attachments, context: context)
                    if Task.isCancelled { return }
                    // Stale generation: a clear or newer request superseded
                    // this one — drop its completion instead of appending.
                    guard generation == self.currentGeneration else { return }
                    await MainActor.run {
                        saveHistory()
                    }
                } catch {
                    if Task.isCancelled { return }
                    guard generation == self.currentGeneration else { return }
                    await MainActor.run {
                        failRequest("Agent execution failed: \(error.localizedDescription)",
                                    systemMessage: error.localizedDescription)
                    }
                }
            }
            activeAgentTask = task
            _ = await task.result
            await MainActor.run {
                // A superseded generation must not clear a newer request's
                // in-flight state.
                guard generation == self.currentGeneration else { return }
                self.isProcessing = false
            }
            return
        }

        // Processing through Chat Mode: Query Model directly and conversationally (no tools/planning)
        // --- COMPREHENSIVE CHAT MODE STATE VALIDATION ---
        let selectedModel = AssistModelManager.shared.selectedModelID
        let selectedProvider = LLMService.shared.provider(for: selectedModel)

        await logger.info("[ChatMode] Validating session state. Model: \(selectedModel), Provider: \(selectedProvider.rawValue)")

        if selectedProvider != .offline && selectedProvider != .codex {
            let key = LLMService.shared.retrieveAPIKey(for: selectedProvider)
            // N-1: mirror the M-7 fix in AssistAgentSession — a valid Google
            // OAuth session satisfies the Google-provider credential check.
            // The old API-key-only gate rejected OAuth-authenticated users
            // holding no API key with a "Missing API key" error.
            let authMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode
            let authService = GoogleAccountAuthService.shared
            var oauthTokenAvailable = false
            if selectedProvider == .google, authMode == "google_oauth", authService.isAuthenticated {
                oauthTokenAvailable = !((try? await authService.getValidAccessToken()) ?? "").isEmpty
            }
            let googleOAuthOK = Self.googleOAuthSatisfiesChatCheck(
                providerIsGoogle: selectedProvider == .google,
                authMode: authMode,
                isAuthenticated: authService.isAuthenticated,
                tokenAvailable: oauthTokenAvailable
            )
            guard !key.isEmpty || googleOAuthOK else {
                // Authenticated-but-tokenless is a session problem, never a
                // "provide an API key" problem (same defect class as C-1).
                let errorMsg: String
                if selectedProvider == .google, authMode == "google_oauth", authService.isAuthenticated {
                    errorMsg = "Chat Validation Failed: Your Google session has expired and SwiftCode couldn't obtain a working access token. Please sign in again in Settings → Assist → Google Account."
                } else {
                    errorMsg = "Chat Validation Failed: Missing API key / credentials for provider \(selectedProvider.rawValue). Please configure your key in Assist Settings."
                }
                await MainActor.run {
                    failRequest(errorMsg)
                }
                return
            }
        } else if selectedProvider == .offline {
            guard FoundationModels.shared.isEnabled else {
                let errorMsg = "Chat Validation Failed: Local Apple Foundation Models are selected but disabled. Please enable them in Assist Settings."
                await MainActor.run {
                    failRequest(errorMsg)
                }
                return
            }
        }
        // ------------------------------------------------
        metrics.mark(.credentialsResolved)

        let chatSystemPrompt = """
        You are SwiftCode Assist, a helpful conversational software engineering assistant.
        Answer the user's request directly and concisely. In Chat mode, do not call tools,
        claim to have inspected files, or say that you changed the project.
        """

        let context = buildContext()
        if contextEngine == nil {
            contextEngine = AssistContextEngine(context: context)
        }

        let messagesCopy = await MainActor.run { self.messages }
        let recentMessages = Self.compactedConversationHistory(from: Array(messagesCopy.suffix(15)))

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
            content: chatSystemPrompt,
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
        let budget = contextEngine!.calculateBudget(modelId: modelId, systemPromptLength: chatSystemPrompt.count)
        let compactedSections = contextEngine!.compactContext(sections: sections, budget: budget)

        await MainActor.run {
            self.modelContext = compactedSections
            self.contextPressure = contextEngine!.getPressureState()
        }

        // --- SystemIndex instruction retrieval (shared, provider-independent) ---
        // Chat mode is conversational (no tools); it carries the short chat
        // system prompt plus selectively retrieved task sections — never the
        // whole instruction corpus.
        await beginInstructionRetrievalPhaseIfNeeded()
        metrics.mark(.systemIndexRetrievalStarted)
        let instructionQuery = InstructionQueryContext(
            userText: trimmed,
            taskCategory: SystemIndexService.classifyCategory(for: trimmed),
            stage: .preparation,
            modelID: selectedModel,
            maxTokens: 3000,
            excludingChunkIDs: activeRetrievalLedger?.retrievedChunkIDs ?? []
        )
        let instructionRetrieval = await SystemIndexService.shared.retrieve(for: instructionQuery)
        metrics.mark(.systemIndexRetrievalCompleted)
        var chatLedger = activeRetrievalLedger ?? SystemIndexRequestLedger()
        chatLedger.record(instructionRetrieval)
        activeRetrievalLedger = chatLedger
        let retrievedInstructionsBlock = instructionRetrieval.formattedForPrompt()
        if !instructionRetrieval.notes.isEmpty {
            await logger.info("SystemIndex (chat): \(instructionRetrieval.notes.joined(separator: " | "))")
        }
        if instructionRetrieval.budgetExceeded {
            lastWarning = instructionRetrieval.notes.joined(separator: " ")
        }

        let baselineSystemPrompt = (try? getSystemPrompt()) ?? SystemIndexService.shared.baselinePrompt()
        var prompt = """
        # SYSTEM PROMPT (CANONICAL ASSIST INSTRUCTIONS)
        \(baselineSystemPrompt)

        # CHAT OPERATING POLICY
        \(chatSystemPrompt)

        \(retrievedInstructionsBlock)

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

        let responseMessage = AssistMessage(role: .assistant, content: "")
        messages.append(responseMessage)
        setRequestPhase(.sendingRequest)
        metrics.mark(.requestCreated)

        let streamProgress = AssistStreamProgressMonitor()
        let messageID = responseMessage.id
        requestMetricsByMessageID[messageID] = metrics
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            // Stale generation: a clear or newer request superseded this one.
            guard generation == self.currentGeneration else { return }
            do {
                metrics.mark(.requestSent)
                try await LLMService.shared.streamChat(
                    messages: [AIMessage(role: .user, content: prompt)],
                    model: modelId,
                    systemPrompt: "",
                    providerOverride: selectedProvider,
                    onToken: { [weak self] token in
                        streamProgress.markProgress()
                        await self?.appendChatToken(token, to: messageID, generation: generation)
                        metrics.mark(.firstTextDelta)
                        metrics.mark(.firstVisibleRender)
                    }
                )
                guard !Task.isCancelled else { return }
                guard generation == self.currentGeneration else { return }
                self.finishChatResponse(messageID: messageID, modelID: modelId, providerID: selectedProvider.rawValue)
                metrics.mark(.responseCompleted)
                metrics.logSummary(modelName: modelId)
            } catch {
                guard !Task.isCancelled else { return }
                guard generation == self.currentGeneration else { return }
                self.finishChatResponse(
                    messageID: messageID,
                    error: error.localizedDescription,
                    timedOut: error is AssistRequestTimeoutError,
                    modelID: modelId,
                    providerID: selectedProvider.rawValue
                )
                metrics.mark(.responseCompleted)
                metrics.logSummary(modelName: modelId)
            }
        }
        activeChatTask = task
        // Progress watchdog: the chat transport exposes no timeout of its own,
        // so a stalled stream must fail explicitly instead of spinning forever.
        let watchdog = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard streamProgress.secondsSinceProgress() > 180 else { continue }
                let shouldTimeout = await MainActor.run { [weak self] () -> Bool in
                    guard let self else { return false }
                    return self.currentGeneration == generation && self.isProcessing
                }
                guard shouldTimeout else { return }
                task.cancel()
                await MainActor.run { [weak self] in
                    self?.finishChatResponse(
                        messageID: messageID,
                        error: AssistRequestTimeoutError.timedOut(180).localizedDescription,
                        timedOut: true,
                        modelID: modelId,
                        providerID: self?.selectedProvider.rawValue
                    )
                }
                return
            }
        }
        await task.value
        watchdog.cancel()
        activeChatTask = nil
        if requestPhase != .cancelled {
            processNextQueuedMessageIfAny()
        }

    }

    private static func isLightweightConversation(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let lightweightTurns: Set<String> = [
            "hi", "hello", "hey", "hello there", "hi there", "hey there",
            "good morning", "good afternoon", "good evening", "thanks", "thank you",
            "thanks a lot", "okay", "ok", "got it", "cool"
        ]
        return lightweightTurns.contains(normalized)
    }

    private static func compactedConversationHistory(from messages: [AssistMessage]) -> [AssistMessage] {
        var remainingCharacters = 12_000
        var selected: [AssistMessage] = []
        for message in messages.reversed() where remainingCharacters > 0 {
            guard !message.content.isEmpty else { continue }
            let content = String(message.content.suffix(min(message.content.count, remainingCharacters)))
            selected.append(AssistMessage(role: message.role, content: content))
            remainingCharacters -= content.count
        }
        return selected.reversed()
    }

    private func appendChatToken(_ token: String, to messageID: UUID, generation: AssistRequestGeneration) {
        // Late tokens from a superseded generation must not resurrect a
        // cleared conversation or pollute a newer one.
        guard generation == currentGeneration else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        var message = messages[index]
        message.content += token
        messages[index] = message
        setRequestPhase(.receivingResponse)
    }

    private func finishChatResponse(messageID: UUID, error: String? = nil, timedOut: Bool = false, modelID: String? = nil, providerID: String? = nil, tokenUsage: AssistTokenUsage? = nil) {
        if let error {
            lastError = "AI request failed: \(error)"
            messages.append(AssistMessage(role: .system, content: lastError ?? "AI request failed."))
        }
        if let index = messages.firstIndex(where: { $0.id == messageID }), messages[index].content.isEmpty, error != nil {
            messages.remove(at: index)
        }
        attributeFinishedMessage(messageID: messageID, modelID: modelID, providerID: providerID, tokenUsage: tokenUsage)
        isProcessing = false
        // Terminal state: the request is over and the UI must not show a
        // spinner for it anymore.
        setRequestPhase(timedOut ? .timedOut : (error != nil ? .failed : .completed))
        saveHistory()
    }

    // MARK: - Turn Attribution (model / provider / token usage)

    /// Resolves the model/provider that actually minted a turn. A router
    /// failover during the turn replaces the settings-selected model, so the
    /// most recent failover since the turn started wins; otherwise the
    /// requested model/provider is reported as-is.
    private func resolvedTurnModel(
        fallbackModelID: String?,
        fallbackProviderID: String?,
        turnStart: Date?
    ) -> (modelID: String?, providerID: String?) {
        let history = AssistModelRouter.shared.failoverHistory
        let relevant: [ModelFailoverEvent]
        if let turnStart {
            relevant = history.filter { $0.timestamp >= turnStart }
        } else {
            relevant = history
        }
        if let last = relevant.last {
            return (last.newModelID, last.newProviderID)
        }
        return (fallbackModelID, fallbackProviderID)
    }

    /// Records model/provider/token-usage attribution on a finished assistant
    /// message, using the real model when a failover happened mid-turn.
    /// No-op when the message no longer exists (e.g. removed empty error turn).
    private func attributeFinishedMessage(
        messageID: UUID,
        modelID: String?,
        providerID: String?,
        tokenUsage: AssistTokenUsage?
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        var message = messages[index]
        let turnStart = requestMetricsByMessageID[messageID]?.messageSubmitted
        let resolved = resolvedTurnModel(fallbackModelID: modelID, fallbackProviderID: providerID, turnStart: turnStart)
        message.modelId = resolved.modelID
        if let provider = resolved.providerID ?? message.providerID {
            message.providerID = provider
        }
        message.tokenUsage = tokenUsage
        messages[index] = message
    }

    // MARK: - Message Queue System

    public func enqueueMessage(_ content: String, attachments: [AgentFileContext] = [], envelope: AssistTaskEnvelope? = nil) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = QueuedAssistMessage(content: trimmed, attachments: attachments, envelope: envelope)
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
        interruptActiveSessionAndSend(content: msg.content, attachments: msg.attachments, envelope: msg.envelope)
    }

    public func interruptActiveSessionAndSend(content: String, attachments: [AgentFileContext] = [], envelope: AssistTaskEnvelope? = nil) {
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
            activeChatTask?.cancel()
            activeChatTask = nil
            activeGoogleCloudTask?.cancel()
            activeGoogleCloudTask = nil
            WorkerRuntimeState.shared.stopAllActiveWorkers(reason: "Interrupted by user for continuation.")
            cancelTerminalExecution()

            // Finalize previous assistant message so its activity group is marked non-executing
            if let idx = messages.indices.last {
                messages[idx].activityGroup?.isExecuting = false
                saveHistory()
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.isProcessing = false
            self.setRequestPhase(.idle)
            await self.sendMessage(trimmed, attachments: attachments, envelope: envelope)
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
            await self.sendMessage(next.content, attachments: next.attachments, envelope: next.envelope)
        }
    }

    public func stopCurrentSession() {
        // Invalidate the generation so late callbacks from the cancelled
        // request are dropped instead of updating the UI afterwards.
        requestGenerationValue += 1

        activeAgentTask?.cancel()
        activeAgentTask = nil

        activeChatTask?.cancel()
        activeChatTask = nil

        activeGoogleCloudTask?.cancel()
        activeGoogleCloudTask = nil

        if let gcSession = activeGoogleCloudSession {
            Task {
                try? await gcSession.cancel()
            }
        }

        agentSession.cancel()

        activeMetaTask?.cancel()
        activeMetaTask = nil
        Task {
            await MetaAssistProvider.shared.cancelTurn()
        }

        WorkerRuntimeState.shared.stopAllActiveWorkers(reason: "Operation stopped by user.")
        PlanQuestionManager.shared.cancelPendingQuestions()
        cancelTerminalExecution()

        isProcessing = false
        setRequestPhase(.cancelled)
        currentCodeReview = nil
        isCodeReviewRunning = false
        if let last = messages.last, last.role == .assistant, last.content.isEmpty, last.activityGroup?.hasContent != true, (last.thinkingContent?.isEmpty ?? true) {
            messages.removeLast()
        }
        if let idx = messages.indices.last {
            if var activity = messages[idx].activityGroup {
                for i in activity.tools.indices where activity.tools[i].status == .running || activity.tools[i].status == .pending {
                    activity.tools[i].status = .cancelled
                    activity.tools[i].result = "Cancelled"
                    let label = activity.tools[i].displayLabel ?? activity.tools[i].toolId
                    activity.tools[i].purpose = "\(label) (Cancelled)"
                }
                activity.isExecuting = false
                messages[idx].activityGroup = activity
            }
        }
        saveHistory()
    }

    public func clearSession() {
        clearChat()
    }

    public func clearChat() {
        // Invalidate the request generation FIRST, before cancelling anything:
        // any late callback, streaming event, tool result, or error update
        // still in flight will see a stale generation and drop its update
        // instead of repopulating the cleared conversation.
        requestGenerationValue += 1
        setRequestPhase(.idle)

        // Immediately cancel the active agent task and agent session
        activeAgentTask?.cancel()
        activeAgentTask = nil

        activeChatTask?.cancel()
        activeChatTask = nil

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

        activeMetaTask?.cancel()
        activeMetaTask = nil
        Task {
            await MetaAssistProvider.shared.cancelTurn()
            await MuseCodeMSPBridge.shared.stopHost()
        }

        // Clean up workers and pending questions
        WorkerRuntimeState.shared.stopAllActiveWorkers(reason: "Chat cleared by user.")
        WorkerRuntimeState.shared.clearAllWorkers()
        PlanQuestionManager.shared.cancelPendingQuestions()

        // Immediately cancel terminal execution and any running sub-processes
        // (also resumes any hung approval continuation as denied).
        cancelTerminalExecution()

        // Reset states to a clean, idle state
        isProcessing = false
        lastError = nil
        lastWarning = nil
        takeoverReason = nil
        currentCodeReview = nil
        isCodeReviewRunning = false
        hasCodeReviewBeenInvoked = false
        activeFallbackMessage = nil
        AssistModelManager.shared.clearFallbackNotification()

        // Clear the full conversation and its transient execution state — not
        // just the visible messages. The shared SystemIndex cache, bundled
        // System Assets, settings, credentials, and project files are
        // intentionally NOT touched.
        // Save previous conversation if it had messages before resetting
        if !messages.isEmpty {
            let snap = messages
            let convId = AssistConversationHistory.shared.activeConversationID ?? AssistConversationHistory.shared.startNewConversation().id
            Task { @MainActor in
                await AssistConversationHistory.shared.saveMessages(conversationId: convId, messages: snap)
                _ = AssistConversationHistory.shared.startNewConversation()
            }
        } else {
            _ = AssistConversationHistory.shared.startNewConversation()
        }

        messages.removeAll()
        // SDK tool panels live in the in-memory store, not on the
        // messages, so clearing the transcript alone left stale rows
        // to render under the next unrelated SDK message.
        SDKToolEventStore.shared.resetAll()
        requestMetricsByMessageID.removeAll()
        modelContext = []
        contextPressure = nil
        contextEngine = nil
        activeRetrievalLedger = nil
        AssistEventNormalizer.shared.resetForNewTask()
        clearQueue()
        session.reset()
        UserDefaults.standard.removeObject(forKey: "com.swiftcode.assist.history")
    }

    public func resetActiveGoogleCloudSessionIfModelChanged(to newModelID: String) {
        if let gcSession = activeGoogleCloudSession, gcSession.config.model != newModelID {
            let sessionToClose = gcSession
            activeGoogleCloudSession = nil
            activeGoogleCloudTask?.cancel()
            activeGoogleCloudTask = nil
            Task {
                try? await sessionToClose.close()
            }
        }
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
        // Snapshot on the caller and persist off the main thread: encoding the
        // full message history to JSON on every send is the largest main-thread
        // stall in the "Preparing request…" window, and it grows with the
        // conversation. UserDefaults is thread-safe; ordering is preserved
        // because each snapshot encodes the state at call time.
        let snapshot = messages
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: "com.swiftcode.assist.history")
            }
        }

        if !snapshot.isEmpty {
            Task { @MainActor in
                let convId = AssistConversationHistory.shared.activeConversationID ?? AssistConversationHistory.shared.startNewConversation().id
                await AssistConversationHistory.shared.saveMessages(conversationId: convId, messages: snapshot)
            }
        }
    }

    // MARK: - Assist with Meta Execution Pipeline

    private func sendMetaAssistMessage(
        _ content: String,
        attachments: [AgentFileContext] = [],
        envelope: AssistTaskEnvelope? = nil,
        metrics: AssistRequestMetrics? = nil,
        generation: AssistRequestGeneration
    ) async {
        guard let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL,
              FileManager.default.fileExists(atPath: projectURL.path) else {
            await MainActor.run {
                failRequest("Execution failed: No active workspace project selected. Please open or select a project directory first.")
            }
            return
        }
        let workspaceRoot = projectURL.path

        // SystemIndex instruction retrieval for Assist with Meta (Muse Code SDK)
        await beginInstructionRetrievalPhaseIfNeeded()
        metrics?.mark(.systemIndexRetrievalStarted)
        let instructionQuery = InstructionQueryContext(
            userText: content,
            taskCategory: SystemIndexService.classifyCategory(for: content),
            stage: .preparation,
            modelID: MetaAssistProvider.defaultModelID,
            maxTokens: 4000,
            excludingChunkIDs: activeRetrievalLedger?.retrievedChunkIDs ?? []
        )
        let instructionRetrieval = await SystemIndexService.shared.retrieve(for: instructionQuery)
        metrics?.mark(.systemIndexRetrievalCompleted)
        var metaLedger = activeRetrievalLedger ?? SystemIndexRequestLedger()
        metaLedger.record(instructionRetrieval)
        activeRetrievalLedger = metaLedger
        if !instructionRetrieval.notes.isEmpty {
            await logger.info("SystemIndex (Meta): \(instructionRetrieval.notes.joined(separator: " | "))")
        }

        await MainActor.run {
            if AppSettings.shared.otherModelsWithMetaSDK || AppSettings.shared.swiftCodeCloudWithMetaSDK {
                let resolved = MuseOtherModelsBridge.shared.resolveActiveModel()
                self.currentActivityStatus = "Contacting Assist with Meta (Bridged: \(resolved.displayName))..."
            } else {
                self.currentActivityStatus = "Contacting Assist with Meta..."
            }
            var initialMsg = AssistMessage(role: .assistant, content: "")
            initialMsg.providerID = MetaAssistProvider.providerID
            self.messages.append(initialMsg)
            self.saveHistory()
            self.setRequestPhase(.sendingRequest)
        }

        let messageID = await MainActor.run { self.messages.last?.id }
        let historySnapshot = await MainActor.run { Array(self.messages.dropLast()) }
        if let messageID {
            await MainActor.run { self.requestMetricsByMessageID[messageID] = metrics }
        }

        let task = Task {
            defer {
                Task { @MainActor in
                    guard generation == self.currentGeneration else { return }
                    self.isProcessing = false
                    if !self.requestPhase.isTerminal {
                        self.setRequestPhase(.idle)
                    }
                    self.processNextQueuedMessageIfAny()
                }
            }

            do {
                try await MetaAssistProvider.shared.executeTurn(
                    prompt: content,
                    history: historySnapshot,
                    workspaceRoot: workspaceRoot,
                    onTextDelta: { [weak self] delta in
                        Task { @MainActor [weak self] in
                            guard let self, generation == self.currentGeneration else { return }
                            self.setRequestPhase(.receivingResponse)
                            if let messageID, let idx = self.messages.firstIndex(where: { $0.id == messageID }) {
                                var msg = self.messages[idx]
                                msg.content += delta
                                self.messages[idx] = msg
                            }
                        }
                    },
                    onThinkingDelta: { [weak self] thoughtDelta in
                        Task { @MainActor [weak self] in
                            guard let self, generation == self.currentGeneration else { return }
                            self.setRequestPhase(.waitingForModel)
                            if let messageID, let idx = self.messages.firstIndex(where: { $0.id == messageID }) {
                                var msg = self.messages[idx]
                                let cur = msg.thinkingContent ?? ""
                                msg.thinkingContent = cur + thoughtDelta
                                self.messages[idx] = msg
                            }
                        }
                    }
                )

                await MainActor.run {
                    guard generation == self.currentGeneration else { return }
                    if let messageID {
                        let metaModelID: String
                        if AppSettings.shared.otherModelsWithMetaSDK || AppSettings.shared.swiftCodeCloudWithMetaSDK {
                            metaModelID = MuseOtherModelsBridge.shared.resolveActiveModel().modelID
                        } else {
                            metaModelID = AppSettings.shared.metaAssistModelID.isEmpty
                                ? MetaAssistProvider.defaultModelID
                                : AppSettings.shared.metaAssistModelID
                        }
                        self.attributeFinishedMessage(
                            messageID: messageID,
                            modelID: metaModelID,
                            providerID: MetaAssistProvider.providerID,
                            tokenUsage: nil
                        )
                    }
                    self.setRequestPhase(.completed)
                    self.saveHistory()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.currentGeneration else { return }
                    let errStr = "Assist with Meta Error: \(error.localizedDescription)"
                    self.lastError = errStr
                    if let messageID, let idx = self.messages.firstIndex(where: { $0.id == messageID }) {
                        if self.messages[idx].content.isEmpty {
                            self.messages[idx].content = errStr
                        } else {
                            self.messages.append(AssistMessage(role: .system, content: errStr))
                        }
                    } else {
                        self.messages.append(AssistMessage(role: .system, content: errStr))
                    }
                    self.setRequestPhase(.failed)
                    self.saveHistory()
                }
            }
        }

        activeMetaTask = task
        _ = await task.result
    }

    // MARK: - Google Cloud SDK / Antigravity Execution Pipeline

    /// Direct (non-agentic) execution path for the SwiftCode Cloud Model.
    /// Bypasses the Antigravity SDK session entirely: no API key, OAuth token,
    /// or routing strategy is required — just the settings toggle and daily quota.
    /// The user message was already appended by sendMessage before this runs.
    private func sendSwiftCodeCloudMessage(
        _ content: String,
        attachments: [AgentFileContext] = [],
        envelope: AssistTaskEnvelope? = nil,
        metrics: AssistRequestMetrics? = nil
    ) async {
        await MainActor.run {
            self.currentActivityStatus = "Contacting SwiftCode Cloud…"
            self.messages.append(AssistMessage(role: .assistant, content: ""))
            self.saveHistory()
        }
        metrics?.mark(.modelResolved)

        // SystemIndex instruction retrieval for SwiftCode Cloud Model
        await beginInstructionRetrievalPhaseIfNeeded()
        metrics?.mark(.systemIndexRetrievalStarted)
        let instructionQuery = InstructionQueryContext(
            userText: content,
            taskCategory: SystemIndexService.classifyCategory(for: content),
            stage: .preparation,
            modelID: AppSettings.shared.selectedAssistModelID,
            maxTokens: 3000,
            excludingChunkIDs: activeRetrievalLedger?.retrievedChunkIDs ?? []
        )
        let instructionRetrieval = await SystemIndexService.shared.retrieve(for: instructionQuery)
        metrics?.mark(.systemIndexRetrievalCompleted)
        var cloudLedger = activeRetrievalLedger ?? SystemIndexRequestLedger()
        cloudLedger.record(instructionRetrieval)
        activeRetrievalLedger = cloudLedger
        let retrievedInstructionsBlock = instructionRetrieval.formattedForPrompt()

        // Recent conversation as context (excluding the placeholder just appended).
        let history: [(role: String, content: String)] = await MainActor.run {
            // Notices (warnings/errors) are UI-only — never model context.
            self.messages.dropLast().filter { $0.noticeLevel == nil }.suffix(12).map { ($0.role.rawValue, $0.content) }
        }

        // Fold decodable text attachments and retrieved instructions into the prompt.
        var prompt = content
        if !retrievedInstructionsBlock.isEmpty {
            prompt = retrievedInstructionsBlock + "\n\n" + prompt
        }
        let attachmentTexts = attachments.compactMap { file -> String? in
            guard let data = Data(base64Encoded: file.base64Content),
                  data.count < 200_000,
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "[Attachment: \(file.filename)]\n\(text)"
        }
        if !attachmentTexts.isEmpty {
            prompt += "\n\n" + attachmentTexts.joined(separator: "\n\n")
        }

        do {
            // The exact server-side model name comes from the selected cloud
            // model ID ("swiftcode-cloud:<name>"). Nil means the legacy
            // single-model selection — the client resolves it to the first
            // discovered model (or the configured fallback).
            let selectedID = AppSettings.shared.selectedAssistModelID
            let endpointModel = SCCloudConfiguration.endpointName(forInternalID: selectedID)
            let baselinePrompt = (try? getSystemPrompt()) ?? SystemIndexService.shared.baselinePrompt()
            let identityDirective = """
            # ASSIST IDENTITY & BEHAVIORAL SAFEGUARDS
            CRITICAL IDENTITY DIRECTIVE: Your name is Assist, the intelligent software engineering assistant built natively inside SwiftCode.
            You are running inside the SwiftCode IDE environment using SwiftCode Cloud Model.
            Regardless of the underlying model host, you MUST ALWAYS identify as Assist and NEVER claim to be any other product or service.
            All system assets and training data retrieved through SystemIndex are your native SwiftCode knowledge base.
            """
            let fullSystemPrompt = identityDirective + "\n\n" + baselinePrompt
            let response = try await SCCloudModelClient.shared.complete(
                prompt: prompt,
                history: history,
                systemPrompt: fullSystemPrompt,
                modelIdentifier: endpointModel
            )
            metrics?.mark(.requestSent)
            await MainActor.run {
                if let idx = self.messages.indices.last {
                    var message = self.messages[idx]
                    message.content = response
                    self.messages[idx] = message
                }
                self.currentActivityStatus = "Idle"
                self.isProcessing = false
                self.saveHistory()
                self.processNextQueuedMessageIfAny()
            }
        } catch {
            let scError = error as? SCCloudError
            let friendly = scError?.userFacingMessage ?? error.localizedDescription
            // Raw API detail for the Server Error dialog — endpoint, status
            // code, and response body straight from the HTTP exchange.
            let detail = ServerErrorDetail(
                endpoint: SCCloudConfiguration.chatURL?.absoluteString ?? SCCloudConfiguration.baseURLString,
                statusCode: scError?.httpStatusCode,
                rawBody: scError?.rawResponseBody ?? error.localizedDescription
            )
            await postNotice(.error, "SwiftCode Cloud Model: \(friendly)", serverError: detail, replacingPlaceholder: true)
            await MainActor.run {
                self.currentActivityStatus = "Idle"
                self.isProcessing = false
                self.saveHistory()
                self.processNextQueuedMessageIfAny()
            }
        }
    }

    private func sendGoogleCloudSDKMessage(
        _ content: String,
        attachments: [AgentFileContext] = [],
        envelope: AssistTaskEnvelope? = nil,
        metrics: AssistRequestMetrics? = nil,
        generation: AssistRequestGeneration
    ) async {
        let runtime = GoogleCloudSDKRuntime.shared
        do {
            try await runtime.ensureStarted()
        } catch {
            await MainActor.run {
                self.failRequest(
                    "Google Antigravity engine failed to start: \(error.localizedDescription)",
                    systemMessage: "Engine error: \(error.localizedDescription)"
                )
            }
            return
        }
        metrics?.mark(.sessionResolved)

        // Merge explicit files from envelope if not already present
        var allAttachments = attachments
        if let env = envelope {
            for file in env.explicitFiles {
                if !allAttachments.contains(where: { $0.filename == file.filename }) {
                    allAttachments.append(file)
                }
            }
        }

        let sdkAttachments: [GoogleCloudSDKAttachment] = allAttachments.map {
            GoogleCloudSDKAttachment(name: $0.filename, path: $0.filename, mimeType: $0.mimeType, content: $0.base64Content)
        }

        // --- Proactive OAuth Scope Verification ---
        // If the user is authenticated via Google account but their stored token lacks
        // the required Antigravity scopes (from legacy sign-in), prompt them to approve
        // the updated permissions rather than hitting an authentication scope error.
        let assistGoogleAuthMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode
        let isGoogleAuthActive = assistGoogleAuthMode == "google_oauth"
        let altKeysEnabled = await MainActor.run { AppSettings.shared.alternativeKeysEnabled }
        let hasAntigravityCreds = GoogleAccountAuthService.shared.fetchAntigravityCredentialsFromKeychain() != nil
        if isGoogleAuthActive && GoogleAccountAuthService.shared.isAuthenticated && !GoogleAccountAuthService.shared.hasRequiredAssistScopes() && !altKeysEnabled && !hasAntigravityCreds {
            await MainActor.run {
                self.isProcessing = false
                self.currentActivityStatus = "Re-authenticating to enable Assist…"
                if let old = self.activeGoogleCloudSession {
                    Task { try? await old.close() }
                }
                self.activeGoogleCloudSession = nil
                let scopeMessage = """
                **Action required — additional permissions needed**

                Your Google account session is missing the permissions needed to use the Gemini API directly without an API key. \
                A sign-in prompt has been opened — please approve the permissions to continue using Assist.
                """
                self.messages.append(AssistMessage(role: .system, content: scopeMessage))
                self.saveHistory()
                GoogleAccountAuthService.shared.reAuthenticateForAssistScopes()
            }
            return
        }

        let initialRouted = await AssistModelRouter.shared.selectModelForSDK(objective: content)

        // SwiftCode Cloud Model: bypass the Antigravity session entirely, even if
        // this path was reached directly. (sendMessage normally routes here first.)
        // Matches every cloud model ID, not just the legacy single-model one.
        if let routed = initialRouted, SCCloudConfiguration.isCloudModelID(routed.model.id) {
            await sendSwiftCodeCloudMessage(content, attachments: allAttachments, envelope: envelope, metrics: metrics)
            return
        }
        var initialConfig = initialRouted?.config ?? GoogleCloudSDKConfiguration.resolveDefault(objective: content)
        let initialModelId = initialRouted?.model.modelIdentifier ?? initialConfig.model
        let initialModelName = initialRouted?.model.displayName ?? (initialConfig.model)
        metrics?.mark(.modelResolved)

        // Validate that credentials exist before initiating execution for Gemini/Google models.
        // The provider comes from the explicit configuration record — never
        // inferred from the model name. (C-2)
        let isGoogleRouted = (initialConfig.provider == "gemini" || initialConfig.provider == "google")
        if isGoogleRouted {
            let hasApiKey = !(initialConfig.apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasOAuth = !(initialConfig.oauthToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if !hasApiKey && !hasOAuth {
                // C-1: reconcile with auth-service state before reporting. The
                // resolved config can be credential-less while the user is
                // authenticated (expired token + failed refresh, incomplete
                // CLI import) — that is a session problem, never a
                // "provide an API key" problem.
                let authMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode
                let authService = GoogleAccountAuthService.shared
                if authMode == "google_oauth" && authService.isAuthenticated {
                    // One recovery attempt through the async accessor (retries
                    // refresh, consults ambient ADC). A recovered token lets
                    // the request continue instead of failing.
                    if let recovered = try? await authService.getValidAccessToken(), !recovered.isEmpty {
                        initialConfig.oauthToken = recovered
                    } else {
                        let refreshNote = authService.lastTokenRefreshError.map { " (\($0))" } ?? ""
                        await MainActor.run {
                            let sessionExpiredMsg = """
                            **Google session expired**

                            Your Google account is still signed in, but SwiftCode couldn't obtain a working access token\(refreshNote). Please sign in again in Settings → Assist → Google Account.

                            Your conversation is preserved.
                            """
                            self.failRequest(sessionExpiredMsg)
                        }
                        return
                    }
                } else {
                    await MainActor.run {
                        self.failRequest("Authentication Error (\(initialModelName)): No valid Gemini API Key or Google OAuth account configured. Please enter your Gemini API key or sign in with Google in Assist Settings.")
                    }
                    return
                }
            }
        }

        let session: GoogleCloudSDKSession

        // --- SystemIndex instruction retrieval (shared, provider-independent) ---
        // The session carries the baseline system instructions (stable, so
        // sessions remain reusable); the task-specific sections retrieved here
        // travel with this request's prompt instead of the whole corpus.
        metrics?.mark(.credentialsResolved)
        await beginInstructionRetrievalPhaseIfNeeded()
        metrics?.mark(.systemIndexRetrievalStarted)
        let instructionQuery = InstructionQueryContext(
            userText: content,
            taskCategory: SystemIndexService.classifyCategory(for: content),
            stage: .preparation,
            modelID: initialModelId,
            maxTokens: 4000,
            excludingChunkIDs: activeRetrievalLedger?.retrievedChunkIDs ?? []
        )
        let instructionRetrieval = await SystemIndexService.shared.retrieve(for: instructionQuery)
        metrics?.mark(.systemIndexRetrievalCompleted)
        var sdkLedger = activeRetrievalLedger ?? SystemIndexRequestLedger()
        sdkLedger.record(instructionRetrieval)
        activeRetrievalLedger = sdkLedger
        let retrievedInstructionsBlock = instructionRetrieval.formattedForPrompt()
        if !instructionRetrieval.notes.isEmpty {
            await logger.info("SystemIndex (Antigravity): \(instructionRetrieval.notes.joined(separator: " | "))")
        }
        if instructionRetrieval.budgetExceeded {
            lastWarning = instructionRetrieval.notes.joined(separator: " ")
        }
        setRequestPhase(.buildingRequest)
        metrics?.mark(.toolsPrepared)
        // C-3: reuse only when the full credential-bearing contract matches
        // (see canReuseSession) — a rotated token or changed quota project
        // must force a new session instead of 401ing on a dead bearer.
        if let existing = activeGoogleCloudSession,
           existing.config.canReuseSession(for: initialConfig) {
            session = existing
        } else {
            if let old = activeGoogleCloudSession {
                await runtime.closeSession(id: old.id)
                activeGoogleCloudSession = nil
            }
            do {
                session = try await runtime.createSession(config: initialConfig)
                activeGoogleCloudSession = session
                activeGoogleCloudModelId = initialModelId
                activeGoogleCloudModelDisplayName = initialModelName
            } catch {
                await logger.error("[AssistManager] Failed to create Antigravity session for \(initialModelName): \(error.localizedDescription)")
                await MainActor.run {
                    failRequest("Session Error (\(initialModelName)): \(error.localizedDescription)")
                }
                return
            }
        }

        let initialActivity = AssistActivityGroup(isExecuting: true)
        await MainActor.run {
            var initialMsg = AssistMessage(role: .assistant, content: "")
            initialMsg.activityGroup = initialActivity
            self.messages.append(initialMsg)
            if let lastID = self.messages.last?.id {
                self.requestMetricsByMessageID[lastID] = metrics
            }
            self.saveHistory()
        }

        let task = Task {
            defer {
                Task { @MainActor in
                    self.isProcessing = false
                    // Never overwrite a terminal phase recorded by the turn
                    // outcome (completed/failed/cancelled/timedOut).
                    if !self.requestPhase.isTerminal {
                        self.setRequestPhase(.idle)
                    }
                }
            }

            var explicitContextPrefix = ""
            if let env = envelope {
                if !env.explicitSkills.isEmpty {
                    explicitContextPrefix += "\n\n# EXPLICITLY SELECTED AGENT SKILLS (MANDATORY EXECUTION)\n"
                    explicitContextPrefix += "The user explicitly selected the following skills using the / command. You MUST strictly follow their procedures and workflows:\n\n"
                    for skill in env.explicitSkills {
                        explicitContextPrefix += "## Skill: \(skill.name)\n"
                        explicitContextPrefix += "Description: \(skill.description)\n"
                        if let content = skill.skillMarkdownContent, !content.isEmpty {
                            explicitContextPrefix += "```markdown\n\(content)\n```\n\n"
                        }
                    }
                }

                if !env.explicitMCPServers.isEmpty {
                    explicitContextPrefix += "\n\n# EXPLICITLY SELECTED MCP SERVERS (MANDATORY EXECUTION)\n"
                    explicitContextPrefix += "The user explicitly designated these MCP servers via the @ command. You MUST route applicable operations to these MCP servers via the `use_mcp` tool. Do not substitute other tools:\n"
                    for server in env.explicitMCPServers {
                        explicitContextPrefix += "- MCP Server: \(server)\n"
                    }
                    explicitContextPrefix += "\n"
                }

                if !env.explicitFiles.isEmpty {
                    explicitContextPrefix += "\n\n# EXPLICITLY DESIGNATED TASK FILES\n"
                    explicitContextPrefix += "The user explicitly designated these files via the @ command. Treat them as authoritative task context:\n"
                    for file in env.explicitFiles {
                        explicitContextPrefix += "- File: \(file.filename)\n"
                    }
                    explicitContextPrefix += "\n"
                }
            }

            let executionModeRaw = UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? ExecutionMode.autopilot.rawValue
            let activeMode = ExecutionMode(rawValue: executionModeRaw) ?? .autopilot
            let modeDirective = """
            # ACTIVE OPERATING MODE: \(activeMode.rawValue.uppercased())
            \(activeMode.systemInstruction)
            """

            let instructionPrefix = (retrievedInstructionsBlock.isEmpty ? "" : retrievedInstructionsBlock + "\n\n") + modeDirective + "\n\n"
            var currentPrompt = instructionPrefix + (explicitContextPrefix.isEmpty ? content : "\(explicitContextPrefix)\n\n# USER REQUEST\n\(content)")
            var currentAttachments = sdkAttachments
            var currentSession: GoogleCloudSDKSession = session
            var currentConfig = initialConfig
            var currentModelId = initialModelId
            var currentModelName = initialModelName
            var attempts = 0
            let maxFailoverAttempts = 3
            var protocolCorrectionAttempts = 0
            var totalIdleTimeoutUsed: TimeInterval = 0
            // Guards the 403 scope-insufficient path: a scope-upgrade re-auth
            // is attempted at most once per user message so a rejected token
            // can never spin an infinite re-authentication loop.
            var didAttemptScopeReauth = false

            executionLoop: while attempts < maxFailoverAttempts {
                guard totalIdleTimeoutUsed < 240 else {
                    let timeoutError = "Assist stopped making progress after 4 minutes without runtime activity. Retry the request, or inspect any active tool before repeating it."
                    await MainActor.run {
                        self.lastError = timeoutError
                        if let idx = self.messages.indices.last {
                            self.messages[idx].content = timeoutError
                            self.messages[idx].activityGroup?.isExecuting = false
                            self.saveHistory()
                        }
                        // Truthful terminal state: timed out, not idle.
                        self.setRequestPhase(.timedOut)
                        self.isProcessing = false
                    }
                    break executionLoop
                }
                attempts += 1
                let watchdogTimeout = min(180, 240 - totalIdleTimeoutUsed)
                let eventStream = await currentSession.subscribeEvents()
                var turnError: String? = nil
                var turnCompletedSuccessfully = false
                var invalidToolPayload = false
                var outputFilter = AssistToolPayloadStreamFilter()
                let watchdog = AssistSDKTurnWatchdog()

                let streamTask = Task { @MainActor in
                    var thinkingStartTime: Date? = nil
                    streamLoop: for await event in eventStream {
                        guard !Task.isCancelled else { break streamLoop }
                        // Stale generation: the conversation was cleared or a
                        // newer request started — drop late events instead of
                        // repopulating the cleared conversation.
                        guard generation == self.currentGeneration else { break streamLoop }
                        watchdog.recordActivity()
                        guard let idx = self.messages.indices.last else { continue }
                        switch event {
                        case .agentStarted:
                            metrics?.mark(.firstEventReceived)
                            metrics?.mark(.modelStarted)
                            self.setRequestPhase(.waitingForModel)

                        case .agentProgress(_, let delta, let thoughtDelta):
                            metrics?.mark(.firstEventReceived)

                            // Handle reasoning / thought stream
                            if let thoughtDelta = thoughtDelta, !thoughtDelta.isEmpty {
                                if thinkingStartTime == nil {
                                    thinkingStartTime = Date()
                                }
                                var message = self.messages[idx]
                                let currentThinking = message.thinkingContent ?? ""
                                message.thinkingContent = currentThinking + thoughtDelta
                                if let start = thinkingStartTime {
                                    message.thinkingDuration = Date().timeIntervalSince(start)
                                }
                                self.messages[idx] = message
                                self.currentActivityStatus = "Thinking…"
                            }

                            // Handle conversational response stream
                            if let delta = delta, !delta.isEmpty {
                                if let start = thinkingStartTime, self.messages[idx].thinkingDuration == nil {
                                    self.messages[idx].thinkingDuration = Date().timeIntervalSince(start)
                                }
                                let safeDelta = outputFilter.append(delta)
                                var message = self.messages[idx]
                                if outputFilter.didSuppressToolPayload {
                                    message.content = ""
                                } else if !safeDelta.isEmpty {
                                    metrics?.mark(.firstTextDelta)
                                    metrics?.mark(.firstVisibleRender)
                                    self.setRequestPhase(.receivingResponse)
                                    message.content += safeDelta
                                }
                                self.messages[idx] = message
                            }
                        case .toolStarted(let tool):
                            metrics?.mark(.firstEventReceived)
                            metrics?.mark(.firstToolCall)
                            metrics?.mark(.toolExecutionStarted)
                            self.setRequestPhase(.executingTool)
                            let argsDict: [String: Any] = (try? JSONSerialization.jsonObject(with: tool.rawArgs.data(using: .utf8) ?? Data())) as? [String: Any] ?? [:]
                            self.reportToolStarted(callId: tool.id, toolName: tool.name, arguments: argsDict)

                        case .toolProgress(let toolId, let msg):
                            self.reportToolProgress(callId: toolId, message: msg)

                        case .toolCompleted(let res):
                            metrics?.mark(.toolExecutionCompleted)
                            self.setRequestPhase(.handlingToolResult)
                            self.reportToolCompleted(callId: res.id, toolName: res.name, output: res.result, arguments: [:])

                        case .toolFailed(let toolId, let name, let err):
                            metrics?.mark(.toolExecutionCompleted)
                            self.setRequestPhase(.handlingToolResult)
                            self.reportToolFailed(callId: toolId, toolName: name, error: err, arguments: [:])

                        case .workerStarted(_, let workerId, let name, let args):
                            self.reportWorkerStarted(workerId: workerId, name: name, args: args)

                        case .workerProgress(_, _, let progress):
                            self.currentActivityStatus = progress

                        case .workerCompleted(_, let workerId, let result):
                            self.reportWorkerCompleted(workerId: workerId, result: result)

                        case .workerFailed(_, let workerId, let error):
                            self.reportWorkerFailed(workerId: workerId, error: error)

                        case .agentCompleted(_, let response, _, let sdkUsage):
                            metrics?.mark(.responseCompleted)
                            metrics?.logSummary()

                            if let start = thinkingStartTime, self.messages[idx].thinkingDuration == nil, self.messages[idx].thinkingContent != nil {
                                self.messages[idx].thinkingDuration = Date().timeIntervalSince(start)
                            }

                            let safeRemainder = outputFilter.finish(fallbackResponse: response)
                            if outputFilter.didSuppressToolPayload {
                                invalidToolPayload = true
                                var message = self.messages[idx]
                                message.content = ""
                                self.messages[idx] = message
                                self.currentActivityStatus = "Correcting tool request format…"
                                break streamLoop
                            }
                            if !safeRemainder.isEmpty {
                                var message = self.messages[idx]
                                message.content += safeRemainder
                                self.messages[idx] = message
                            }

                            if watchdog.didTimeOut {
                                turnError = "Assist stopped receiving runtime events and cancelled this turn. Please retry; if a specific tool is still running, inspect its result before repeating it."
                                if var activity = self.messages[idx].activityGroup {
                                    for tIdx in activity.tools.indices where activity.tools[tIdx].status == .running {
                                        activity.tools[tIdx].status = .failed
                                        activity.tools[tIdx].result = "Timed out waiting for tool/runtime progress"
                                    }
                                    activity.isExecuting = false
                                    self.messages[idx].activityGroup = activity
                                }
                                break streamLoop
                            }

                            if var activity = self.messages[idx].activityGroup {
                                for tIdx in activity.tools.indices where activity.tools[tIdx].status == .running {
                                    activity.tools[tIdx].status = .failed
                                    activity.tools[tIdx].result = "Turn ended before tool reported completion"
                                    let label = activity.tools[tIdx].displayLabel ?? activity.tools[tIdx].toolId
                                    activity.tools[tIdx].purpose = "\(label) (Unreported)"
                                }
                                activity.isExecuting = false
                                self.messages[idx].activityGroup = activity
                            }

                            let currentContent = self.messages[idx].content
                            let finalContent = currentContent.isEmpty ? response : currentContent
                            var finalMessage = self.messages[idx]
                            finalMessage.content = finalContent
                            self.messages[idx] = finalMessage
                            self.messages[idx].activityGroup?.isExecuting = false
                            let turnTokenUsage = sdkUsage.map {
                                AssistTokenUsage(
                                    promptTokens: $0.promptTokens,
                                    completionTokens: $0.completionTokens,
                                    totalTokens: $0.totalTokens
                                )
                            }
                            self.attributeFinishedMessage(
                                messageID: self.messages[idx].id,
                                modelID: self.activeGoogleCloudModelId ?? initialModelId,
                                providerID: initialConfig.provider,
                                tokenUsage: turnTokenUsage
                            )
                            self.saveHistory()
                            self.setRequestPhase(.completed)
                            self.isProcessing = false
                            turnCompletedSuccessfully = true
                            break streamLoop

                        case .agentFailed(_, let err):
                            turnError = err

                            if var activity = self.messages[idx].activityGroup {
                                for tIdx in activity.tools.indices where activity.tools[tIdx].status == .running {
                                    activity.tools[tIdx].status = .failed
                                    activity.tools[tIdx].result = err
                                }
                                self.messages[idx].activityGroup = activity
                            }
                            break streamLoop

                        case .error(let msg):
                            turnError = msg

                            if var activity = self.messages[idx].activityGroup {
                                for tIdx in activity.tools.indices where activity.tools[tIdx].status == .running {
                                    activity.tools[tIdx].status = .failed
                                    activity.tools[tIdx].result = msg
                                }
                                self.messages[idx].activityGroup = activity
                            }
                            break streamLoop

                        default:
                            break
                        }
                    }
                }

                watchdog.start(timeout: watchdogTimeout) { [weak self] in
                    guard let self else { return }
                    self.currentActivityStatus = "No Assist activity for \(Int(watchdogTimeout / 60)) minutes — stopping this turn…"
                    streamTask.cancel()
                    try? await currentSession.cancel()
                }

                metrics?.mark(.requestSent)
                if GoogleAccountAuthService.shared.isAuthenticated {
                    await MainActor.run {
                        AntigravityQuotaService.shared.recordRequest()
                    }
                }
                do {
                    try await currentSession.sendMessage(currentPrompt, attachments: currentAttachments)
                    _ = await streamTask.result
                } catch {
                    streamTask.cancel()
                    turnError = error.localizedDescription
                }
                watchdog.stop()

                if watchdog.didTimeOut {
                    totalIdleTimeoutUsed += watchdogTimeout
                    turnCompletedSuccessfully = false
                    turnError = "Assist stopped receiving runtime events for \(Int(watchdogTimeout)) seconds and cancelled this attempt. Please retry, or inspect any active tool before repeating it."
                    await MainActor.run {
                        if let idx = self.messages.indices.last, var activity = self.messages[idx].activityGroup {
                            for tIdx in activity.tools.indices where activity.tools[tIdx].status == .running {
                                activity.tools[tIdx].status = .failed
                                activity.tools[tIdx].result = "Timed out waiting for tool/runtime progress"
                            }
                            activity.isExecuting = false
                            self.messages[idx].activityGroup = activity
                        }
                    }
                }

                if turnCompletedSuccessfully {
                    break executionLoop
                }

                if invalidToolPayload {
                    if protocolCorrectionAttempts == 0 {
                        protocolCorrectionAttempts += 1
                        currentPrompt = """
                        The previous assistant response was an internal tool-request payload printed as normal text. No action from that payload was executed. Continue the user's original request using only the structured tool-calling interface enabled in this session. Do not repeat, quote, reinterpret, or execute anything from the invalid payload, and do not repeat tool operations whose results are already in the conversation. If no tool is needed, answer normally in plain text.
                        """
                        currentAttachments = []
                        await MainActor.run {
                            if let idx = self.messages.indices.last {
                                self.messages[idx].content = ""
                                self.messages[idx].activityGroup?.isExecuting = true
                            }
                            self.currentActivityStatus = "Retrying with a valid structured tool call…"
                        }
                        continue executionLoop
                    }

                    let protocolError = "The model returned an invalid tool-call format twice. No command from that text was executed. Retry the request or select a different model/toolkit."
                    await MainActor.run {
                        self.lastError = protocolError
                        if let idx = self.messages.indices.last {
                            self.messages[idx].content = protocolError
                            self.messages[idx].activityGroup?.isExecuting = false
                            self.saveHistory()
                        }
                        self.setRequestPhase(.failed)
                        self.isProcessing = false
                    }
                    break executionLoop
                }

                let altKeysEnabled = await MainActor.run { AppSettings.shared.alternativeKeysEnabled }
                let savedModelsEnabled = await MainActor.run { AppSettings.shared.useSavedModels }
                let isGemini = currentModelId.lowercased().contains("gemini") || currentModelName.lowercased().contains("gemini") || (currentConfig.provider == "gemini" || currentConfig.provider == "google")

                if let errText = turnError {
                    // --- Classified auth error handling ---
                    // A 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT is only fixable by
                    // re-authentication when the stored token was minted before
                    // the required Developer API scope existed. Otherwise the
                    // endpoint is rejecting a correctly-scoped token (missing
                    // quota project, wrong endpoint, or a product restriction):
                    // re-authenticating would loop forever, so the actual
                    // restriction is explained instead. Account mode is never
                    // silently switched to API-key mode here.
                    let classification = GoogleAuthErrorClassification.classify(errText)
                    let isQuotaOrRateLimit: Bool = {
                        if case .quotaOrRateLimit = classification.kind { return true }
                        return AssistModelRouter.shared.isQuotaOrRateLimit(errorText: errText)
                    }()

                    if case .scopeInsufficient(let storedScopes) = classification.kind {
                        let hasCloudPlatform = storedScopes?.contains("cloud-platform") ?? false
                        let hasAntigravity = GoogleAccountAuthService.shared.fetchAntigravityCredentialsFromKeychain() != nil
                        let needsScopeUpgrade = !(storedScopes?.contains("generative-language.retriever") ?? false) && !hasCloudPlatform && !hasAntigravity
                        if needsScopeUpgrade && !didAttemptScopeReauth && GoogleAccountAuthService.shared.isAuthenticated {
                            // One-shot scope upgrade: the new sign-in requests
                            // the Developer API scope the old token lacks.
                            didAttemptScopeReauth = true
                            await MainActor.run {
                                if let idx = self.messages.indices.last {
                                    self.messages[idx].activityGroup?.isExecuting = false
                                    self.messages[idx].content = ""
                                }
                                self.isProcessing = false
                                self.currentActivityStatus = "Re-authenticating to enable Assist…"
                                if let old = self.activeGoogleCloudSession {
                                    Task { try? await old.close() }
                                }
                                self.activeGoogleCloudSession = nil
                                let scopeMessage = """
                                **Action required — additional permissions needed**

                                Your Google account session was created before SwiftCode requested the Gemini API permission it needs. \
                                A sign-in prompt has been opened — please approve the permissions to continue using Assist.
                                """
                                self.messages.append(AssistMessage(role: .system, content: scopeMessage))
                                self.saveHistory()
                                GoogleAccountAuthService.shared.reAuthenticateForAssistScopes()
                            }
                            break executionLoop
                        }
                        // Not fixable by re-authentication: report the actual
                        // restriction with the preserved diagnostics, keep the
                        // conversation and the selected auth mode intact, and do
                        // not fall through into API-key rotation.
                        await MainActor.run {
                            if let idx = self.messages.indices.last {
                                self.messages[idx].activityGroup?.isExecuting = false
                            }
                            self.isProcessing = false
                            self.setRequestPhase(.failed)
                            if let old = self.activeGoogleCloudSession {
                                Task { try? await old.close() }
                            }
                            self.activeGoogleCloudSession = nil
                            let diagnostics = classification.diagnosticSummary
                            let restrictionMessage = """
                            **Google account authentication failed**

                            The Gemini API rejected the request (\(diagnostics)) even though your \
                            Google session already carries the required permissions. Signing in again \
                            will not fix this.

                            What to check:
                            1. **Google Cloud project** — OAuth requests to the Gemini API must \
                            carry a quota project. Set your project ID in Settings → Assist → \
                            Google Account. Usage is billed to that project (Google's documented \
                            account-authentication contract).
                            2. **API enablement** — the Generative Language API must be enabled \
                            for that project in the Google Cloud console.

                            Your Antigravity IDE subscription quota is not accessible to \
                            third-party applications — Google does not authorize that integration.

                            Your conversation and sign-in are preserved. You can also switch to \
                            API Key mode explicitly in Settings → Assist → Google Account.
                            """
                            self.messages.append(AssistMessage(role: .assistant, content: restrictionMessage))
                            self.lastError = restrictionMessage
                            self.saveHistory()
                        }
                        break executionLoop
                    }

                    let isQuota = AssistModelRouter.shared.isQuotaOrRateLimit(errorText: errText)
                    let isPermanentAuth = errText.contains("401") || errText.contains("403") || errText.contains("API_KEY_INVALID") || errText.contains("invalid api key")

                    // 1. Alternative Keys Rotation (Gemini only)
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
                                    self.setRequestPhase(.failed)
                                    self.isProcessing = false
                                }
                                break executionLoop
                            }
                        }
                    }

                    // H-1: stale-token recovery. A 401/403 on a Google OAuth
                    // session is often a bearer that expired mid-conversation
                    // while the Keychain copy was refreshed — try one token
                    // refresh and retry the same model before quarantining the
                    // provider and failing over to an unrelated model.
                    let turnFailureClass = AssistModelRouter.shared.classify(error: NSError(domain: "AssistManager", code: -1, userInfo: [NSLocalizedDescriptionKey: errText]))
                    let isGoogleOAuthTurn = (currentConfig.provider == "gemini" || currentConfig.provider == "google")
                        && (UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode) == "google_oauth"
                        && GoogleAccountAuthService.shared.isAuthenticated
                        && !altKeysEnabled
                    if turnFailureClass == .authenticationFailed && isGoogleOAuthTurn {
                        // Config-shaped failure: without a quota project,
                        // OAuth calls to the Developer API deterministically
                        // fail. Surface the one-line fix instead of
                        // quarantining the provider and failing over.
                        let quotaProject = AppSettings.shared.assistGoogleCloudProject.trimmingCharacters(in: .whitespacesAndNewlines)
                        if quotaProject.isEmpty {
                            await MainActor.run {
                                let quotaMsg = """
                                **Google account authentication failed**

                                The request was rejected and no Google Cloud quota project is configured. OAuth requests to the Gemini API must carry a quota project — set your project ID in Settings → Assist → Google Account. Your sign-in is intact; set the project and retry.

                                Your conversation is preserved.
                                """
                                self.lastError = quotaMsg
                                if let idx = self.messages.indices.last {
                                    self.messages[idx].activityGroup?.isExecuting = false
                                    self.messages[idx] = AssistMessage(role: .assistant, content: quotaMsg)
                                } else {
                                    self.messages.append(AssistMessage(role: .assistant, content: quotaMsg))
                                }
                                self.saveHistory()
                                self.setRequestPhase(.failed)
                                self.isProcessing = false
                            }
                            break executionLoop
                        }
                        if let refreshed = try? await GoogleAccountAuthService.shared.getValidAccessToken(),
                           !refreshed.isEmpty, refreshed != (currentConfig.oauthToken ?? "") {
                            // The bearer rotated since this session was
                            // created: close the stale session and retry the
                            // same model with the fresh token.
                            await logger.warning("[AssistManager] OAuth token rotated mid-conversation; retrying '\(currentModelName)' with the refreshed token.")
                            await runtime.closeSession(id: currentSession.id)
                            currentConfig.oauthToken = refreshed
                            do {
                                let newSession = try await runtime.createSession(config: currentConfig)
                                await MainActor.run {
                                    self.activeGoogleCloudSession = newSession
                                    self.currentActivityStatus = "Refreshing Google session — retrying"
                                    if let idx = self.messages.indices.last {
                                        self.messages[idx].content = ""
                                        self.messages[idx].thinkingContent = ""
                                        self.messages[idx].activityGroup?.isExecuting = true
                                    }
                                }
                                currentSession = newSession
                                continue executionLoop
                            } catch {
                                turnError = error.localizedDescription
                                continue executionLoop
                            }
                        }
                        // Refresh yielded no new token: fall through to
                        // quarantine + failover for a true auth failure.
                    }

                    // 2. Multi-Provider Failover
                    let priorOutput = await MainActor.run { self.messages.last?.content ?? "" }
                    await postNotice(.warning, "Model '\(currentModelName)' failed: \(errText)")
                    if let failover = await AssistModelRouter.shared.handleTurnFailure(
                        failedModelIdentifier: currentModelId,
                        errorText: errText,
                        originalPrompt: content,
                        priorTurnOutput: priorOutput
                    ) {
                        let oldName = currentModelName
                        let newName = failover.nextModel.displayName
                        await postNotice(.warning, "Model '\(oldName)' failed. Failing over to '\(newName)'. Error: \(errText)")
                        metrics?.mark(.followUpRequestInitiated)
                        await MainActor.run {
                            self.currentActivityStatus = "\(oldName) error — switching to \(newName)"
                            self.requestPhase = .fallingBack
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
                            // Preserve the retrieved task instructions across
                            // failover: the continuation prompt replaces the
                            // original request, but the task-specific sections
                            // retrieved for it are still authoritative.
                            currentPrompt = instructionPrefix + failover.continuationPrompt
                            currentAttachments = []
                            continue executionLoop
                        } catch {
                            turnError = error.localizedDescription
                            currentModelId = failover.nextModel.modelIdentifier
                            continue executionLoop
                        }
                    }

                    // No failover and automatic switching is off:
                    // never switch, and never fail silently. Show
                    // the wait (model + reason + that switching is
                    // off) in the activity status, keep the turn in
                    // .waitingForModel, and retry the SAME model on
                    // the next loop iteration. The loop is already
                    // bounded (maxFailoverAttempts), so this waits
                    // and retries instead of hanging forever; when
                    // it finally exhausts, the terminal message
                    // below says explicitly that no other model
                    // was tried.
                    if !AppSettings.shared.assistAutomaticallySwitchModels {
                        let waitDetail = "Waiting on '\(currentModelName)' — automatic model switching is off, so Assist will not switch to another model. Last error: \(errText)"
                        await postNotice(.warning, waitDetail)
                        await MainActor.run {
                            self.currentActivityStatus = waitDetail
                            self.requestPhase = .waitingForModel
                            if let idx = self.messages.indices.last {
                                self.messages[idx].activityGroup?.isExecuting = true
                            }
                        }
                        if attempts < maxFailoverAttempts {
                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                            turnError = "Automatic model switching is off, so no other model was tried; retrying '\(currentModelName)'."
                            continue executionLoop
                        }
                        turnError = "Automatic model switching is off, so no other model was tried. Last error from '\(currentModelName)': \(errText)"
                    }
                }

                // Terminal failure
                let rawErr = turnError ?? ((altKeysEnabled && isGemini) ? "All configured Gemini API keys are currently unavailable." : "\(currentModelName) execution failed")
                let finalErrorMsg = "Error (\(currentModelName)): \(rawErr)"
                // C-3: a terminal authentication failure poisons the session
                // (its bearer is dead). Close and drop it so the next request
                // starts clean instead of reusing dead credentials.
                let terminalClass = AssistModelRouter.shared.classify(error: NSError(domain: "AssistManager", code: -1, userInfo: [NSLocalizedDescriptionKey: rawErr]))
                if terminalClass == .authenticationFailed {
                    await runtime.closeSession(id: currentSession.id)
                    await MainActor.run { self.activeGoogleCloudSession = nil }
                }
                // Red, expandable notice message (also recorded in the log feed).
                await postNotice(.error, finalErrorMsg, replacingPlaceholder: true)
                await MainActor.run {
                    self.lastError = finalErrorMsg
                    if let idx = self.messages.indices.last {
                        self.messages[idx].activityGroup?.isExecuting = false
                    }
                    self.setRequestPhase(.failed)
                    self.isProcessing = false
                }
                break executionLoop
            }
        }

        activeGoogleCloudTask = task
        _ = await task.result
        await MainActor.run {
            self.isProcessing = false
            // Terminal phase was set by the turn outcome (completed/failed);
            // only fall back to idle when no terminal phase was recorded.
            if !self.requestPhase.isTerminal {
                self.setRequestPhase(.idle)
            }
            self.processNextQueuedMessageIfAny()
        }
    }

    // MARK: - Live Tool & Activity Reporting

    private func targetMessageIndexForActivity() -> Int? {
        if let idx = self.messages.indices.reversed().first(where: { self.messages[$0].role == .assistant || self.messages[$0].activityGroup != nil }) {
            return idx
        }
        return self.messages.indices.last
    }

    @MainActor
    public func updateLastAssistantMessageContent(_ content: String) {
        if let idx = self.messages.indices.reversed().first(where: { self.messages[$0].role == .assistant }) {
            var msg = self.messages[idx]
            msg.content = content
            self.messages[idx] = msg
        }
    }

    @MainActor
    public func reportToolStarted(callId: String, toolName: String, arguments: [String: Any], isMuseSDKTool: Bool = false) {
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        self.currentActivityStatus = formatted.runningLabel

        guard let idx = self.targetMessageIndexForActivity() else { return }
        var activity = self.messages[idx].activityGroup ?? AssistActivityGroup(isExecuting: true)

        AssistEventNormalizer.shared.normalizeToolStarted(
            callId: callId,
            toolName: toolName,
            arguments: arguments,
            isMuseSDKTool: isMuseSDKTool,
            in: &activity
        )

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportToolProgress(callId: String, message: String) {
        self.currentActivityStatus = message

        guard let idx = self.targetMessageIndexForActivity() else { return }
        guard var activity = self.messages[idx].activityGroup else { return }

        AssistEventNormalizer.shared.normalizeToolProgress(
            callId: callId,
            message: message,
            in: &activity
        )

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportToolCompleted(callId: String, toolName: String, output: String?, arguments: [String: Any], isMuseSDKTool: Bool = false) {
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        self.currentActivityStatus = formatted.completedLabel

        guard let idx = self.targetMessageIndexForActivity() else { return }
        guard var activity = self.messages[idx].activityGroup else { return }

        AssistEventNormalizer.shared.normalizeToolCompleted(
            callId: callId,
            toolName: toolName,
            output: output,
            arguments: arguments,
            isMuseSDKTool: isMuseSDKTool,
            in: &activity
        )

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportToolFailed(callId: String, toolName: String, error: String, arguments: [String: Any], isMuseSDKTool: Bool = false) {
        let formatted = AssistToolActivityFormatter.format(toolId: toolName, arguments: arguments)
        let cleanError = AssistEventNormalizer.shared.sanitizeErrorMessage(rawError: error, toolName: toolName)
        self.currentActivityStatus = "\(formatted.failedLabel) — \(cleanError)"

        guard let idx = self.targetMessageIndexForActivity() else { return }
        guard var activity = self.messages[idx].activityGroup else { return }

        AssistEventNormalizer.shared.normalizeToolFailed(
            callId: callId,
            toolName: toolName,
            error: error,
            arguments: arguments,
            in: &activity
        )

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func finalizeCurrentThinkingDuration(_ duration: TimeInterval) {
        if let targetIdx = targetMessageIndexForActivity() {
            if self.messages[targetIdx].thinkingDuration == nil && self.messages[targetIdx].thinkingContent != nil {
                self.messages[targetIdx].thinkingDuration = max(0.5, duration)
            }
        }
    }

    @MainActor
    public func reportWorkerStarted(workerId: String, name: String, args: String) {
        let cleanName = name.replacingOccurrences(of: "start_subagent", with: "")
            .replacingOccurrences(of: "Worker:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanName.isEmpty ? "Worker" : "Worker · \(cleanName)"
        self.currentActivityStatus = "\(title)..."

        guard let idx = self.messages.indices.last else { return }
        var activity = self.messages[idx].activityGroup ?? AssistActivityGroup(isExecuting: true)

        AssistEventNormalizer.shared.normalizeWorkerStarted(
            workerId: workerId,
            name: name,
            args: args,
            in: &activity
        )

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportWorkerCompleted(workerId: String, result: String) {
        self.currentActivityStatus = "Worker completed"

        guard let idx = self.messages.indices.last else { return }
        guard var activity = self.messages[idx].activityGroup else { return }

        AssistEventNormalizer.shared.normalizeWorkerCompleted(
            workerId: workerId,
            result: result,
            in: &activity
        )

        self.messages[idx].activityGroup = activity
    }

    @MainActor
    public func reportWorkerFailed(workerId: String, error: String) {
        let cleanErr = AssistEventNormalizer.shared.sanitizeErrorMessage(rawError: error, toolName: "worker")
        self.currentActivityStatus = "Worker failed — \(cleanErr)"

        guard let idx = self.messages.indices.last else { return }
        guard var activity = self.messages[idx].activityGroup else { return }

        AssistEventNormalizer.shared.normalizeWorkerFailed(
            workerId: workerId,
            error: error,
            in: &activity
        )

        self.messages[idx].activityGroup = activity
    }
}

/// Suppresses malformed tool requests accidentally emitted as assistant text.
/// Only complete, recognizable tool-call envelopes are hidden; normal prose
/// continues to stream without waiting for a full model response.
struct AssistToolPayloadStreamFilter {
    private enum Mode {
        case undecided
        case json
        case fenceHeader
        case fencedJSON
        case passthrough
        case suppressed
    }

    private var mode: Mode = .undecided
    private var pending = ""
    private var inspectedText = ""
    private var receivedText = false
    private(set) var didSuppressToolPayload = false
    private let maximumCandidateLength = 256_000

    mutating func append(_ delta: String) -> String {
        guard !delta.isEmpty else { return "" }
        // The format decision is only meaningful before normal prose has been
        // released. Re-scanning an ever-growing response for every token made
        // long streamed answers needlessly quadratic.
        switch mode {
        case .passthrough:
            return delta
        case .suppressed:
            return ""
        case .undecided, .json, .fenceHeader, .fencedJSON:
            break
        }

        receivedText = true
        inspectedText = String((inspectedText + delta).suffix(maximumCandidateLength))
        if Self.hasStrongToolRequestSignature(in: inspectedText) {
            mode = .suppressed
            didSuppressToolPayload = true
            pending = ""
            return ""
        }

        switch mode {
        case .passthrough:
            return delta
        case .suppressed:
            return ""
        case .undecided, .json, .fenceHeader, .fencedJSON:
            pending += delta
        }

        switch mode {
        case .undecided:
            return decideInitialFormat()
        case .json:
            return inspectJSONCandidate()
        case .fenceHeader:
            return inspectFenceHeader()
        case .fencedJSON:
            return inspectFencedJSON()
        case .passthrough, .suppressed:
            return ""
        }
    }

    mutating func finish(fallbackResponse: String) -> String {
        if Self.hasStrongToolRequestSignature(in: fallbackResponse) || Self.containsToolRequestPayload(in: fallbackResponse) {
            mode = .suppressed
            didSuppressToolPayload = true
            pending = ""
            return ""
        }

        if !receivedText {
            return append(fallbackResponse)
        }

        switch mode {
        case .undecided, .json, .fenceHeader, .fencedJSON:
            let remainder = pending
            mode = .passthrough
            pending = ""
            return remainder
        case .passthrough, .suppressed:
            return ""
        }
    }

    private mutating func decideInitialFormat() -> String {
        let leading = pending.drop(while: \.isWhitespace)
        if leading.isEmpty {
            if pending.count > 128 { return releaseAsNormalText() }
            return ""
        }

        if leading.first == "{" {
            mode = .json
            return inspectJSONCandidate()
        }

        let fence = "```"
        let leadingString = String(leading)
        if fence.hasPrefix(leadingString), leadingString.count < fence.count {
            return ""
        }
        if leadingString.hasPrefix(fence) {
            mode = .fenceHeader
            return inspectFenceHeader()
        }

        return releaseAsNormalText()
    }

    private mutating func inspectJSONCandidate() -> String {
        if pending.count > maximumCandidateLength {
            return releaseAsNormalText()
        }
        guard let parsed = Self.firstJSONObject(in: pending) else {
            return ""
        }
        guard Self.isToolRequestObject(parsed.value) else { return releaseAsNormalText() }
        mode = .suppressed
        didSuppressToolPayload = true
        pending = ""
        return ""
    }

    private mutating func inspectFenceHeader() -> String {
        guard pending.firstIndex(of: "\n") != nil else {
            return pending.count > 96 ? releaseAsNormalText() : ""
        }
        let normalized = String(pending.drop(while: \.isWhitespace))
        guard let headerEnd = normalized.firstIndex(of: "\n") else { return "" }
        let header = String(normalized[..<headerEnd]).lowercased()
        guard header.hasPrefix("```"), header.contains("json") else {
            return releaseAsNormalText()
        }
        mode = .fencedJSON
        return inspectFencedJSON()
    }

    private mutating func inspectFencedJSON() -> String {
        if pending.count > maximumCandidateLength {
            return releaseAsNormalText()
        }
        let trimmed = String(pending.drop(while: \.isWhitespace))
        guard let newline = trimmed.firstIndex(of: "\n"),
              let closingFence = trimmed.range(of: "```", range: newline..<trimmed.endIndex) else {
            return ""
        }
        let body = String(trimmed[trimmed.index(after: newline)..<closingFence.lowerBound])
        guard Self.containsToolRequestPayload(in: body) else {
            return releaseAsNormalText()
        }
        mode = .suppressed
        didSuppressToolPayload = true
        pending = ""
        return ""
    }

    private mutating func releaseAsNormalText() -> String {
        mode = .passthrough
        let output = pending
        pending = ""
        return output
    }

    private static func containsToolRequestPayload(in text: String) -> Bool {
        let lowercased = text.lowercased()
        guard lowercased.contains("\"arguments\"") || lowercased.contains("\"input\"") || lowercased.contains("\"tool_calls\"") else {
            return false
        }

        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let openBrace = text[searchStart...].firstIndex(of: "{") {
            let candidate = String(text[openBrace...])
            guard let parsed = firstJSONObject(in: candidate) else { return false }
            if isToolRequestObject(parsed.value) { return true }
            guard let next = text.index(openBrace, offsetBy: candidate.distance(from: candidate.startIndex, to: parsed.end), limitedBy: text.endIndex), next < text.endIndex else {
                return false
            }
            searchStart = next
        }
        return false
    }

    private static func hasStrongToolRequestSignature(in text: String) -> Bool {
        let value = text.lowercased()
        if value.contains("\"function_name\"") && value.contains("\"arguments\"") { return true }
        if value.contains("\"toolid\"") && value.contains("\"input\"") { return true }
        let hasArguments = value.contains("\"arguments\"")
        if value.contains("{") && value.contains("\"name\"") && hasArguments { return true }
        let hasCommandFields = ["\"commandline\"", "\"toolaction\"", "\"toolsummary\"", "\"waitmsbeforeasync\"", "\"notificationtimeoutseconds\""].contains(where: { value.contains($0) })
        return hasArguments && hasCommandFields
    }

    private static func firstJSONObject(in text: String) -> (value: [String: Any], end: String.Index)? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var isInsideString = false
        var isEscaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let end = text.index(after: index)
                    let data = Data(text[start..<end].utf8)
                    let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                    return value.map { ($0, end) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func isToolRequestObject(_ object: [String: Any]) -> Bool {
        let hasArguments = object["arguments"] is [String: Any] || object["arguments"] is [Any]
        let hasInput = object["input"] is [String: Any] || object["input"] is [Any]
        if object["toolId"] is String && hasInput { return true }
        if object["function_name"] is String && hasArguments { return true }
        if object["name"] is String && hasArguments { return true }
        if object["tool_calls"] is [Any] { return true }
        if object["function_call"] is [String: Any] { return true }
        return false
    }
}

@MainActor
final class AssistSDKTurnWatchdog {
    private var lastActivity = Date()
    private var task: Task<Void, Never>?
    private(set) var didTimeOut = false

    func recordActivity() {
        lastActivity = Date()
    }

    func start(timeout: TimeInterval, onTimeout: @escaping @MainActor () async -> Void) {
        lastActivity = Date()
        didTimeOut = false
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if Date().timeIntervalSince(self.lastActivity) >= timeout {
                    self.didTimeOut = true
                    await onTimeout()
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
