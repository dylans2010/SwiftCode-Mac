import Foundation
import os

public actor AgentOrchestrator {
    private let pipelineLogger = Logger(subsystem: "com.swiftcode.app", category: "AgentPipeline")
    private let provider: AIProvider
    private let contextBuilder = AgentContextBuilder()
    private let toolRegistry = AgentToolRegistry.shared

    private var isCancelled = false

    public init(provider: AIProvider = OpenRouterAIProvider.shared) {
        self.provider = provider
    }

    public func runTurn(session: AgentSession, userMessage: String, attachments: [AgentAttachment] = []) async throws {
        isCancelled = false
        pipelineLogger.info("[runTurn] Starting turn. User message: \(userMessage, privacy: .public). Attachments count: \(attachments.count).")

        // Ensure skills are discovered
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        pipelineLogger.info("[runTurn] Discovering skills in directory: \(projectRoot.path).")
        try await SkillsRuntime.shared.discoverSkills(in: projectRoot)

        await MainActor.run {
            session.turnState = .awaitingModel
        }

        var contents: [AgentMessageContent] = [.text(userMessage)]
        for attachment in attachments {
            pipelineLogger.info("[runTurn] Processing attachment: \(attachment.name, privacy: .public).")
            if attachment.type == .image {
                let data = try Data(contentsOf: attachment.url)
                contents.append(.image(data: data, mimeType: "image/jpeg"))
            } else {
                let text = try String(contentsOf: attachment.url, encoding: .utf8)
                contents.append(.text("File content of \(attachment.name):\n\n\(text)"))
            }
        }

        let message = AgentMessage(role: .user, content: contents)
        await MainActor.run {
            session.messages.append(message)
        }

        try await runLoop(session: session)
    }

    public func resumeTurn(session: AgentSession, result: String, toolCallId: String) async throws {
        pipelineLogger.info("[resumeTurn] Resuming turn for toolCallId: \(toolCallId, privacy: .public).")
        let toolResultMessage = AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: toolCallId, content: result))])
        await MainActor.run {
            session.messages.append(toolResultMessage)
        }
        try await runLoop(session: session)
    }

    public func cancel() {
        pipelineLogger.info("[cancel] Cancelling active turn.")
        isCancelled = true
    }

    private func runLoop(session: AgentSession) async throws {
        var shouldContinue = true
        let model = OpenRouterModel(id: "openai/gpt-4o", name: "GPT-4o", description: "Internal Model", contextLength: 1048576, pricing: .init(prompt: "0", completion: "0"))

        pipelineLogger.info("[runLoop] Entering run loop.")

        while shouldContinue && !isCancelled {
            await MainActor.run {
                session.turnState = .awaitingModel
            }

            let isChatMode = await MainActor.run { session.mode == .chat }
            let sessionMessages = await MainActor.run { session.messages }

            pipelineLogger.info("[runLoop] Building context. Total message count: \(sessionMessages.count). Mode: \(isChatMode ? "Chat" : "Agent", privacy: .public).")
            let messages = await contextBuilder.buildContext(messages: sessionMessages, model: model, includeCodebaseContext: true)
            let tools = toolRegistry.schema()

            var assistantContent: [AgentMessageContent] = []

            // Model Routing Selection Single Source of Truth
            let selectedModel = await MainActor.run { AppSettings.shared.selectedAssistModelID }
            let isAppleModel = selectedModel == "AFM 3 Core" || selectedModel == "AFM 3 Core Advanced"
            let isFMEnabled = await MainActor.run { FoundationModels.shared.isEnabled } && isAppleModel
            let stream: AsyncThrowingStream<AgentStreamEvent, Error>

            if isFMEnabled {
                pipelineLogger.info("[runLoop] Foundation Models are enabled. Routing to Apple private on-device reasoning.")
                stream = AsyncThrowingStream { continuation in
                    Task {
                        do {
                            let lastPrompt = messages.last?.content.compactMap { content -> String? in
                                if case .text(let text) = content { return text }
                                return nil
                            }.joined(separator: " ") ?? ""

                            try await FoundationModels.shared.streamPrivateResponse(prompt: lastPrompt) { token in
                                continuation.yield(.text(token))
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            } else {
                let actualModel = selectedModel == "swiftcode-balanced" ? "openai/gpt-4o" : selectedModel
                pipelineLogger.info("[runLoop] OpenRouter provider selected. Selected Model: \(selectedModel, privacy: .public). Actual Model: \(actualModel, privacy: .public). Calling streaming API.")
                stream = try await provider.streamAgentTurn(model: actualModel, messages: messages, tools: isChatMode ? nil : tools)
            }

            var currentText = ""

            // Create a placeholder assistant message that we append tokens to in real-time
            let assistantMessageId = UUID()
            await MainActor.run {
                let initialMessage = AgentMessage(id: assistantMessageId, role: .assistant, content: [.text("")])
                session.messages.append(initialMessage)
            }

            pipelineLogger.info("[runLoop] Consuming stream events...")
            for try await event in stream {
                if isCancelled {
                    pipelineLogger.info("[runLoop] Cancellation detected during stream consumption.")
                    break
                }

                switch event {
                case .text(let delta):
                    currentText += delta
                    // Update assistant message with streaming tokens in real-time!
                    await MainActor.run {
                        if let index = session.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            session.messages[index].content = [.text(currentText)]
                        }
                    }
                case .toolCall(let toolCalls):
                    pipelineLogger.info("[runLoop] Received tool calls count: \(toolCalls.count).")
                    for call in toolCalls {
                        assistantContent.append(.toolCall(call))
                    }
                }
            }

            if isCancelled {
                pipelineLogger.info("[runLoop] Cancellation detected before finalizing content.")
                break
            }

            // Finalize the content
            pipelineLogger.info("[runLoop] Stream consumed. Finalizing assistant content on the main actor.")
            await MainActor.run {
                if let index = session.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    var finalContent: [AgentMessageContent] = []
                    if !currentText.isEmpty {
                        finalContent.append(.text(currentText))
                    }
                    finalContent.append(contentsOf: assistantContent)
                    session.messages[index].content = finalContent
                }
            }

            let toolCalls = assistantContent.compactMap { content -> AgentToolCall? in
                if case .toolCall(let call) = content { return call }
                return nil
            }

            if toolCalls.isEmpty || isChatMode {
                pipelineLogger.info("[runLoop] No tool calls parsed or running in Chat Mode. Loop termination imminent.")
                shouldContinue = false
            } else {
                pipelineLogger.info("[runLoop] Parsing and executing \(toolCalls.count) tool calls.")
                await MainActor.run {
                    session.turnState = .executingTools
                }
                for call in toolCalls {
                    if isCancelled {
                        pipelineLogger.info("[runLoop] Cancellation detected during tool execution.")
                        break
                    }

                    let args = decodeArguments(call.arguments)
                    pipelineLogger.info("[runLoop] Executing tool: \(call.name, privacy: .public). Arguments: \(call.arguments, privacy: .public).")

                    // Special Tool Handling
                    if call.name == "ask_user" {
                        pipelineLogger.info("[runLoop] Tool 'ask_user' detected. Awaiting user response.")
                        await MainActor.run {
                            handleAskUser(call, args, session)
                            session.turnState = .awaitingUserAnswer
                        }
                        shouldContinue = false
                        break
                    } else if call.name == "questions_handle" {
                        pipelineLogger.info("[runLoop] Tool 'questions_handle' detected. Awaiting user responses.")
                        await MainActor.run {
                            handleQuestionsHandle(call, args, session)
                            session.turnState = .awaitingUserAnswer
                        }
                        shouldContinue = false
                        break
                    } else if call.name == "checklist_plan" {
                        pipelineLogger.info("[runLoop] Tool 'checklist_plan' detected. Updating plan.")
                        await MainActor.run {
                            handleChecklistPlan(args, session)
                        }
                    }

                    do {
                        let result = try await toolRegistry.execute(name: call.name, arguments: args)
                        pipelineLogger.info("[runLoop] Tool \(call.name, privacy: .public) executed successfully.")
                        await MainActor.run {
                            session.messages.append(AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: call.id, content: result))]))
                        }
                    } catch {
                        pipelineLogger.error("[runLoop] Tool \(call.name, privacy: .public) failed with error: \(error.localizedDescription, privacy: .public).")
                        await MainActor.run {
                            session.messages.append(AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: call.id, content: error.localizedDescription, isError: true))]))
                        }
                    }
                }
            }
        }

        pipelineLogger.info("[runLoop] Exiting loop. Finalizing state.")
        await MainActor.run {
            if !shouldContinue && session.turnState != .awaitingUserAnswer {
                session.turnState = .idle
            }
        }
    }

    @MainActor
    private func handleAskUser(_ call: AgentToolCall, _ args: [String: any Sendable], _ session: AgentSession) {
        if let questionText = args["question"] as? String {
            let inputTypeStr = args["input_type"] as? String
            let inputType: AgentPendingQuestion.InputType = inputTypeStr == "selection" ? .selection(options: args["options"] as? [String] ?? []) : .text
            let question = AgentPendingQuestion(question: questionText, inputType: inputType)

            if let index = session.messages.indices.last {
                session.messages[index].content.append(.pendingQuestion(question))
            }
        }
    }

    @MainActor
    private func handleQuestionsHandle(_ call: AgentToolCall, _ args: [String: any Sendable], _ session: AgentSession) {
        if let questionsData = args["questions"] as? [[String: any Sendable]] {
            let questions = questionsData.compactMap { qDict -> AgentPendingQuestion? in
                guard let prompt = qDict["prompt"] as? String,
                      let inputTypeStr = qDict["input_type"] as? String else { return nil }
                let inputType: AgentPendingQuestion.InputType = inputTypeStr == "selection" ? .selection(options: qDict["options"] as? [String] ?? []) : .text
                return AgentPendingQuestion(question: prompt, inputType: inputType)
            }
            let set = AgentPendingQuestionSet(questions: questions)

            if let index = session.messages.indices.last {
                session.messages[index].content.append(.pendingQuestionSet(set))
            }
        }
    }

    @MainActor
    private func handleChecklistPlan(_ args: [String: any Sendable], _ session: AgentSession) {
        if let tasksData = args["tasks"] as? [[String: any Sendable]] {
            let tasks = tasksData.compactMap { tDict -> AgentChecklistTask? in
                guard let id = tDict["id"] as? String,
                      let title = tDict["title"] as? String,
                      let statusStr = tDict["status"] as? String,
                      let status = AgentChecklistTaskStatus(rawValue: statusStr) else { return nil }
                return AgentChecklistTask(id: id, title: title, status: status, detail: tDict["detail"] as? String)
            }
            session.checklist = AgentChecklistState(tasks: tasks)
        }
    }

    private func decodeArguments(_ arguments: String) -> [String: any Sendable] {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return [:]
        }

        var result: [String: any Sendable] = [:]

        for (key, value) in dict {
            switch value {
            case let v as String: result[key] = v
            case let v as Int: result[key] = v
            case let v as Double: result[key] = v
            case let v as Float: result[key] = v
            case let v as Bool: result[key] = v
            case let v as [String]: result[key] = v
            case let v as [Int]: result[key] = v
            case let v as [Double]: result[key] = v
            case let v as [Bool]: result[key] = v
            case let v as [[String: Any]]:
                result[key] = v.map { item in
                    var converted: [String: any Sendable] = [:]
                    for (k, val) in item {
                        if let s = val as? String { converted[k] = s }
                        else if let i = val as? Int { converted[k] = i }
                        else if let d = val as? Double { converted[k] = d }
                        else if let b = val as? Bool { converted[k] = b }
                        else if let a = val as? [String] { converted[k] = a }
                    }
                    return converted
                }
            default:
                break
            }
        }

        return result
    }
}
