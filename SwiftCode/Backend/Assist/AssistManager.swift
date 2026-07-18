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
        return AssistModelOption.all.first(where: { $0.id == modelID }) ?? .swiftCodeBalanced
    }

    private var selectedProvider: AssistModelProvider {
        let providerRawValue = UserDefaults.standard.string(forKey: "assist.selectedProvider") ?? AssistModelProvider.openAI.rawValue
        return AssistModelProvider(rawValue: providerRawValue) ?? .openAI
    }

    private init() {
        AssistExecutionFunctions.initializeRegistry()
        loadHistory()
        setupAgent()
    }

    private func setupAgent() {
        let context = buildContext()
        self.api.configure(context: context)
        self.agent = AssistAgent(context: context, registry: registry)
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
            do {
                try await agentSession.start(objective: trimmed, attachments: attachments, context: context)
                await MainActor.run {
                    messages.append(AssistMessage(role: .assistant, content: "Autonomous task execution finished."))
                    isProcessing = false
                    saveHistory()
                }
            } catch {
                await MainActor.run {
                    lastError = "Agent execution failed: \(error.localizedDescription)"
                    messages.append(AssistMessage(role: .system, content: error.localizedDescription))
                    isProcessing = false
                    saveHistory()
                }
            }
            return
        }

        // Processing through Chat Mode: Query Model directly and conversationally (no tools/planning)
        do {
            // --- COMPREHENSIVE CHAT MODE STATE VALIDATION ---
            let selectedModel = AssistModelManager.shared.selectedModelID
            let selectedProvider = LLMService.shared.provider(for: selectedModel)

            logger.log("[ChatMode] Validating session state. Model: \(selectedModel), Provider: \(selectedProvider.rawValue)")

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

            if !attachments.isEmpty {
                prompt += "\n# ATTACHED FILES FOR THIS TASK (READ-ONLY REFERENCE)\n"
                for file in attachments {
                    prompt += "Filename: \(file.filename)\n"
                    prompt += "Extension: \(file.extension)\n"
                    prompt += "MIME Type: \(file.mimeType)\n"
                    prompt += "Size: \(file.size) bytes\n"
                    prompt += "Base64 Content:\n\(file.base64Content)\n"
                    prompt += "-----------------------------\n"
                }
            }

            prompt += "\n# CONVERSATION HISTORY\n"
            let messagesCopy = await MainActor.run { self.messages }
            for msg in messagesCopy.suffix(15) {
                let roleStr = msg.role == .user ? "User" : (msg.role == .system ? "System" : "Assistant")
                prompt += "\(roleStr): \(msg.content)\n"
            }

            prompt += "\nAssistant:"

            let response = await AssistLLMService.generateResponse(
                prompt: prompt,
                provider: selectedProvider,
                apiKey: APIKeyManager.shared.retrieveKey(service: selectedProvider.apiKeyProvider),
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
