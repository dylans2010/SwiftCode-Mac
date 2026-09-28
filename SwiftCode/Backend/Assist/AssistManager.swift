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

    public let logger = AssistLogger()
    public let session = AssistSession()
    public let agentSession = AssistAgentSession()
    public let registry = AssistToolRegistry()
    private let permissions = AssistPermissionsManager()
    private let memory = AssistMemoryGraph()

    private var agent: AssistAgent?
    private let api = AssistAPI.shared
    private var activeAgentTask: Task<Void, Never>?

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

        // Prevent concurrent agent sessions on the shared AssistAgentSession instance.
        guard !isProcessing else {
            await MainActor.run {
                messages.append(AssistMessage(role: .system, content: "A task is already in progress. Please wait for it to finish or stop it before starting a new one."))
                saveHistory()
            }
            return
        }

        await MainActor.run {
            messages.append(AssistMessage(role: .user, content: trimmed, attachments: attachments))
            isProcessing = true
            lastError = nil
            saveHistory()
        }

        let isAgentMode = UserDefaults.standard.bool(forKey: "com.swiftcode.assist.mode")
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
                do {
                    try await agentSession.start(objective: trimmed, attachments: attachments, context: context)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        messages.append(AssistMessage(role: .assistant, content: "Autonomous task execution finished."))
                        isProcessing = false
                        saveHistory()
                    }
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        lastError = "Agent execution failed: \(error.localizedDescription)"
                        messages.append(AssistMessage(role: .system, content: error.localizedDescription))
                        isProcessing = false
                        saveHistory()
                    }
                }
            }
            activeAgentTask = task
            _ = await task.result
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
                saveHistory()
            }
        } catch {
            await MainActor.run {
                let errorMsg = "Failed to run chat assistant: \(error.localizedDescription)"
                lastError = errorMsg
                messages.append(AssistMessage(role: .system, content: errorMsg))
                isProcessing = false
                saveHistory()
            }
        }
    }

    public func clearChat() {
        // Immediately cancel the active agent task and agent session
        activeAgentTask?.cancel()
        activeAgentTask = nil

        agentSession.cancel()

        // Immediately cancel terminal execution and any running sub-processes
        cancelTerminalExecution()

        // Reset states to a clean, idle state
        isProcessing = false
        lastError = nil
        takeoverReason = nil
        currentCodeReview = nil
        isCodeReviewRunning = false
        hasCodeReviewBeenInvoked = false
        activeFallbackMessage = nil
        AssistModelManager.shared.clearFallbackNotification()

        messages.removeAll()
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
}
