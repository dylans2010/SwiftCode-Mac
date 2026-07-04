import Foundation

public actor AgentOrchestrator {
    private let provider: AIProvider
    private let contextBuilder = AgentContextBuilder()
    private let toolRegistry = AgentToolRegistry.shared

    private var isCancelled = false

    public init(provider: AIProvider = OpenRouterAIProvider.shared) {
        self.provider = provider
    }

    public func runTurn(session: inout AgentSession, userMessage: String, attachments: [AgentAttachment] = []) async throws {
        isCancelled = false

        // Ensure skills are discovered
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        try await SkillsRuntime.shared.discoverSkills(in: projectRoot)

        session.turnState = .awaitingModel

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
        session.messages.append(message)

        try await runLoop(session: &session)
    }

    public func resumeTurn(session: inout AgentSession, result: String, toolCallId: String) async throws {
        let toolResultMessage = AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: toolCallId, content: result))])
        session.messages.append(toolResultMessage)
        try await runLoop(session: &session)
    }

    public func cancel() {
        isCancelled = true
    }

    private func runLoop(session: inout AgentSession) async throws {
        var shouldContinue = true
        let model = OpenRouterModel(id: "openai/gpt-4.1", name: "GPT-4.1", contextLength: 1048576)

        while shouldContinue && !isCancelled {
            session.turnState = .awaitingModel
            let messages = await contextBuilder.buildContext(messages: session.messages, model: model)
            let tools = toolRegistry.schema()

            var assistantContent: [AgentMessageContent] = []
            let stream = try await provider.streamAgentTurn(model: model.id, messages: messages, tools: tools)

            var currentText = ""
            for try await event in stream {
                if isCancelled { break }

                switch event {
                case .text(let delta):
                    currentText += delta
                case .toolCall(let toolCalls):
                    for call in toolCalls {
                        assistantContent.append(.toolCall(call))
                    }
                }
            }

            if !currentText.isEmpty {
                assistantContent.insert(.text(currentText), at: 0)
            }

            let assistantMessage = AgentMessage(role: .assistant, content: assistantContent)
            session.messages.append(assistantMessage)

            if isCancelled { break }

            let toolCalls = assistantContent.compactMap { content -> AgentToolCall? in
                if case .toolCall(let call) = content { return call }
                return nil
            }

            if toolCalls.isEmpty {
                shouldContinue = false
            } else {
                session.turnState = .executingTools
                for call in toolCalls {
                    if isCancelled { break }

                    let args = decodeArguments(call.arguments)

                    // Special Tool Handling
                    if call.name == "ask_user" {
                        handleAskUser(call, args, &session)
                        shouldContinue = false
                        break
                    } else if call.name == "questions_handle" {
                        handleQuestionsHandle(call, args, &session)
                        shouldContinue = false
                        break
                    } else if call.name == "checklist_plan" {
                        handleChecklistPlan(args, &session)
                    }

                    do {
                        let result = try await toolRegistry.execute(name: call.name, arguments: args)
                        session.messages.append(AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: call.id, content: result))]))
                    } catch {
                        session.messages.append(AgentMessage(role: .assistant, content: [.toolResult(AgentToolResult(toolCallId: call.id, content: error.localizedDescription, isError: true))]))
                        // If a tool fails, we still want the model to see the error and decide next steps
                    }
                }
            }
        }

        if !shouldContinue && session.turnState != .awaitingUserAnswer {
            session.turnState = .idle
        }
    }

    private func handleAskUser(_ call: AgentToolCall, _ args: [String: any Sendable], _ session: inout AgentSession) {
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

    private func handleQuestionsHandle(_ call: AgentToolCall, _ args: [String: any Sendable], _ session: inout AgentSession) {
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

    private func handleChecklistPlan(_ args: [String: any Sendable], _ session: inout AgentSession) {
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
