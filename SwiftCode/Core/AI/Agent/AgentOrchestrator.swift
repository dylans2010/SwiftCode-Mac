import Foundation

public actor AgentOrchestrator {
    private let provider: AIProvider
    private let contextBuilder = AgentContextBuilder()
    private let toolRegistry = AgentToolRegistry.shared

    private var isCancelled = false

    public init(provider: AIProvider = OpenRouterAIProvider.shared) {
        self.provider = provider
    }

    public func runTurn(session: AgentSession, userMessage: String, attachments: [AgentAttachment] = [], mode: AIAssistantMode = .chat) async throws {
        isCancelled = false

        // Ensure skills are discovered
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        try await SkillsRuntime.shared.discoverSkills(in: projectRoot)

        await MainActor.run {
            session.turnState = .awaitingModel
        }

        var contents: [AgentMessageContent] = [.text(userMessage)]
        for attachment in attachments {
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

        try await runLoop(session: session, mode: mode)
    }

    public func resumeTurn(session: AgentSession, result: String, toolCallId: String) async throws {
        let toolResultMessage = AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: toolCallId, content: result))])
        await MainActor.run {
            session.messages.append(toolResultMessage)
        }
        try await runLoop(session: session, mode: .agent)
    }

    public func cancel() {
        isCancelled = true
    }

    private func runLoop(session: AgentSession, mode: AIAssistantMode) async throws {
        var shouldContinue = true

        // Get the selected model ID from AppSettings on the MainActor
        let selectedModelID = await MainActor.run {
            let modelID = AppSettings.shared.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return modelID.isEmpty ? "openai/gpt-4o-mini" : modelID
        }

        let model = OpenRouterModel(id: selectedModelID, name: "Selected Model", description: "Configured Model", contextLength: 1048576, pricing: .init(prompt: "0", completion: "0"))

        while shouldContinue && !isCancelled {
            await MainActor.run {
                session.turnState = .awaitingModel
            }

            // Build historical context from the session messages
            let messages = await MainActor.run {
                session.messages
            }
            let contextMessages = await contextBuilder.buildContext(messages: messages, model: model)

            // In Chat Mode, never pass any tools so tool calling is physically impossible
            let tools = (mode == .chat) ? nil : toolRegistry.schema()

            let stream: AsyncThrowingStream<AgentStreamEvent, Error>

            // Step 3: Single source of truth for Apple Foundation Models
            let isFMEnabled = await FoundationModels.shared.isEnabled
            if isFMEnabled {
                // Route directly to Apple Foundation Models APIs and bypass OpenRouter
                let lastMsgPrompt = await MainActor.run {
                    session.messages.last?.content.compactMap { content -> String? in
                        if case .text(let t) = content { return t }
                        return nil
                    }.joined(separator: "\n") ?? ""
                }

                stream = AsyncThrowingStream { continuation in
                    Task {
                        do {
                            try await FoundationModels.shared.streamPrivateResponse(prompt: lastMsgPrompt) { token in
                                continuation.yield(.text(token))
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            } else {
                stream = try await provider.streamAgentTurn(model: model.id, messages: contextMessages, tools: tools)
            }

            // Real-time streaming UI updates
            let assistantMessageId = UUID()
            await MainActor.run {
                let initialMessage = AgentMessage(id: assistantMessageId, role: .assistant, content: [.text("")])
                session.messages.append(initialMessage)
            }

            var currentText = ""
            var assistantContent: [AgentMessageContent] = []

            for try await event in stream {
                if isCancelled { break }

                switch event {
                case .text(let delta):
                    currentText += delta
                    await MainActor.run {
                        if let index = session.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                            session.messages[index].content = [.text(currentText)]
                        }
                    }
                case .toolCall(let toolCalls):
                    for call in toolCalls {
                        assistantContent.append(.toolCall(call))
                    }
                }
            }

            var finalContents: [AgentMessageContent] = []
            if !currentText.isEmpty {
                finalContents.append(.text(currentText))
            }
            for content in assistantContent {
                if case .toolCall = content {
                    finalContents.append(content)
                }
            }

            await MainActor.run {
                if let index = session.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                    session.messages[index].content = finalContents
                }
            }

            if isCancelled { break }

            let toolCalls = (mode == .chat) ? [] : assistantContent.compactMap { content -> AgentToolCall? in
                if case .toolCall(let call) = content { return call }
                return nil
            }

            if toolCalls.isEmpty {
                shouldContinue = false
            } else {
                await MainActor.run {
                    session.turnState = .executingTools
                }

                for call in toolCalls {
                    if isCancelled { break }

                    let args = decodeArguments(call.arguments)

                    // Special Tool Handling
                    if call.name == "ask_user" {
                        await MainActor.run {
                            handleAskUser(call, args, session)
                        }
                        shouldContinue = false
                        break
                    } else if call.name == "questions_handle" {
                        await MainActor.run {
                            handleQuestionsHandle(call, args, session)
                        }
                        shouldContinue = false
                        break
                    } else if call.name == "checklist_plan" {
                        await MainActor.run {
                            handleChecklistPlan(args, session)
                        }
                    }

                    do {
                        let result = try await toolRegistry.execute(name: call.name, arguments: args)
                        await MainActor.run {
                            session.messages.append(AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: call.id, content: result))]))
                        }
                    } catch {
                        await MainActor.run {
                            session.messages.append(AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: call.id, content: error.localizedDescription, isError: true))]))
                        }
                    }
                }
            }
        }

        if !shouldContinue {
            await MainActor.run {
                if session.turnState != .awaitingUserAnswer {
                    session.turnState = .idle
                }
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
            session.turnState = .awaitingUserAnswer
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
            session.turnState = .awaitingUserAnswer
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
