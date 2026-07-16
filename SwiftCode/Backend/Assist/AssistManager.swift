import Foundation
import Combine

@MainActor
public final class AssistManager: ObservableObject {
    public static let shared = AssistManager()

    @Published public var messages: [AssistMessage] = []
    @Published public var isProcessing = false
    @Published public var lastError: String?
    @Published public var takeoverReason: String?

    public let logger = AssistLogger()
    public let session = AssistSession()
    public let registry = AssistToolRegistry()
    private let permissions = AssistPermissionsManager()
    private let memory = AssistMemoryGraph()

    private var agent: AssistAgent?
    private let api = AssistAPI.shared

    public var selectedModel: AssistModelOption {
        let modelID = AssistModelManager.shared.selectedModelID
        return AssistModelOption.all.first(where: { $0.id == modelID }) ?? .gpt4oMini
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
            fileSystem: AssistFileSystem(workspaceRoot: ProjectManager.shared.currentProject?.directoryURL ?? URL(fileURLWithPath: "/")),
            git: AssistGitManager(project: ProjectManager.shared.currentProject)
        )
        return builder.buildContext(sessionId: session.id)
    }

    public func sendMessage(_ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            messages.append(AssistMessage(role: .user, content: trimmed))
            isProcessing = true
            lastError = nil
            saveHistory()
        }

        let provider = selectedProvider
        let apiKey = APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

        if apiKey == nil || apiKey?.isEmpty == true {
            let error = "Missing API key for \(provider.rawValue). Add a key in Assist Settings."
            await MainActor.run {
                lastError = error
                messages.append(AssistMessage(role: .system, content: error))
                isProcessing = false
                saveHistory()
            }
            return
        }

        guard let agent = self.agent else {
            let error = "Assist agent is unavailable."
            await MainActor.run {
                lastError = error
                messages.append(AssistMessage(role: .system, content: error))
                isProcessing = false
                saveHistory()
            }
            return
        }

        // Processing through the agent (which now uses the AssistAPI internally)
        let response = await agent.processIntent(trimmed)

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
