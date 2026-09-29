import Foundation
import os

@MainActor
public struct PlanAskUserTool: AssistTool {
    public let id: String = "plan-AskUser"
    public let name: String = "Ask User for Decision"
    public let description: String = """
    Presents a structured question to the user during Plan mode execution. \
    The question is rendered as a native macOS UI (PlanUserAskView) and execution \
    suspends until the user provides an answer. The answer becomes persistent session data. \
    This tool is ONLY available in Plan mode and is blocked at the runtime registry layer \
    in Autopilot mode.
    """

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Presents a question to the user and waits for their answer. Only available in Plan mode.",
            properties: [
                "question": JSONSchema(type: "string", description: "The decision question to present to the user."),
                "allowsMultipleAnswers": JSONSchema(type: "boolean", description: "Whether multiple choices may be selected."),
                "choices": JSONSchema(
                    type: "array",
                    description: "Available choices for the user. Each choice must have 'choice' (string) and 'assistRecommended' (boolean) fields.",
                    items: [
                        "type": JSONSchema(type: "object"),
                        "properties": [
                            "choice": JSONSchema(type: "string", description: "The text of this choice option."),
                            "assistRecommended": JSONSchema(type: "boolean", description: "Whether Assist recommends this choice. Informational only — does not imply user approval.")
                        ],
                        "required": ["choice", "assistRecommended"]
                    ]
                ),
                "userSpecification": JSONSchema(type: "boolean", description: "Whether the user may provide a free-form response.")
            ],
            required: ["question", "allowsMultipleAnswers", "choices"]
        )
    }

    public var capability: ToolCapability { .planning }
    public var riskLevel: ToolRiskLevel { .safeRead }
    public var isReadOnly: Bool { true }
    public var isMutating: Bool { false }
    public var estimatedCost: Double { 0.0 }

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "PlanAskUserTool")

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let mode = context.sessionExecutionMode

        guard mode == .plan else {
            logger.warning("[plan-AskUser] Blocked: tool invoked in \(mode.rawValue) mode. Only available in Plan mode.")
            return .failure("plan-AskUser is only available in Plan mode. Current mode: \(mode.rawValue).")
        }

        guard let question = input["question"] as? String, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required argument: 'question' must be a non-empty string.")
        }

        let allowsMultiple = input["allowsMultipleAnswers"] as? Bool ?? false
        let userSpec = input["userSpecification"] as? Bool ?? false

        var choices: [PlanQuestionChoice] = []
        if let choicesRaw = input["choices"] as? [[String: Any]] {
            for raw in choicesRaw {
                if let choiceText = raw["choice"] as? String {
                    let recommended = raw["assistRecommended"] as? Bool ?? false
                    choices.append(PlanQuestionChoice(choice: choiceText, assistRecommended: recommended))
                }
            }
        }

        if choices.isEmpty && !userSpec {
            return .failure("At least one choice is required when userSpecification is false.")
        }

        let questionID = UUID()
        let planQuestion = PlanQuestion(
            id: questionID,
            sessionID: context.sessionId,
            question: question,
            allowsMultipleAnswers: allowsMultiple,
            choices: choices,
            userSpecification: userSpec,
            status: .pending,
            createdAt: Date()
        )

        logger.info("[plan-AskUser] Presenting question: \(question.prefix(60))")

        await MainActor.run {
            PlanQuestionManager.shared.present(question: planQuestion)
        }

        let answer = await PlanQuestionManager.shared.waitForAnswer(questionID: questionID)

        guard let answer = answer else {
            return .failure("Question was cancelled or timed out.")
        }

        await MainActor.run {
            PlanQuestionManager.shared.resolve(questionID: questionID, answer: answer)
        }

        let answerText: String
        switch answer {
        case .selectedChoices(let selected):
            answerText = selected.joined(separator: ", ")
        case .freeForm(let text):
            answerText = text
        }

        logger.info("[plan-AskUser] User answered: \(answerText.prefix(60))")

        return .success(
            "Question: \(question)\nAnswer: \(answerText)",
            data: [
                "questionID": questionID.uuidString,
                "answer": answerText,
                "question": question
            ]
        )
    }
}

public struct PlanQuestionChoice: Codable, Sendable, Identifiable {
    public let id: UUID
    public let choice: String
    public let assistRecommended: Bool

    public init(id: UUID = UUID(), choice: String, assistRecommended: Bool) {
        self.id = id
        self.choice = choice
        self.assistRecommended = assistRecommended
    }
}

public enum PlanQuestionStatus: String, Codable, Sendable {
    case pending = "pending"
    case answered = "answered"
    case cancelled = "cancelled"
    case expired = "expired"
    case resolved = "resolved"
}

public enum PlanQuestionAnswer: Codable, Sendable {
    case selectedChoices([String])
    case freeForm(String)
}

public struct PlanQuestion: Codable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID
    public let question: String
    public let allowsMultipleAnswers: Bool
    public let choices: [PlanQuestionChoice]
    public let userSpecification: Bool
    public var status: PlanQuestionStatus
    public let createdAt: Date
    public var answer: PlanQuestionAnswer?
    public var answeredAt: Date?
    public var associatedStep: String?

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        question: String,
        allowsMultipleAnswers: Bool,
        choices: [PlanQuestionChoice],
        userSpecification: Bool,
        status: PlanQuestionStatus = .pending,
        createdAt: Date = Date(),
        answer: PlanQuestionAnswer? = nil,
        answeredAt: Date? = nil,
        associatedStep: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.question = question
        self.allowsMultipleAnswers = allowsMultipleAnswers
        self.choices = choices
        self.userSpecification = userSpecification
        self.status = status
        self.createdAt = createdAt
        self.answer = answer
        self.answeredAt = answeredAt
        self.associatedStep = associatedStep
    }
}

@MainActor
public final class PlanQuestionManager: ObservableObject {
    public static let shared = PlanQuestionManager()

    @Published public var currentQuestion: PlanQuestion?
    @Published public var questionHistory: [PlanQuestion] = []

    private var answerContinuations: [UUID: CheckedContinuation<PlanQuestionAnswer?, Never>] = [:]
    private let persistenceKey = "com.swiftcode.plan.questions"

    private init() {}

    public func present(question: PlanQuestion) {
        currentQuestion = question
        questionHistory.append(question)
        persistQuestions()
    }

    public func waitForAnswer(questionID: UUID) async -> PlanQuestionAnswer? {
        if let existing = questionHistory.first(where: { $0.id == questionID }), let answer = existing.answer {
            return answer
        }

        return await withCheckedContinuation { continuation in
            answerContinuations[questionID] = continuation
        }
    }

    public func waitForAnswer(questionID: UUID, timeout: TimeInterval) async -> PlanQuestionAnswer? {
        if let existing = questionHistory.first(where: { $0.id == questionID }), let answer = existing.answer {
            return answer
        }

        return await withTaskGroup(of: PlanQuestionAnswer?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    answerContinuations[questionID] = continuation
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

    public func resolve(questionID: UUID, answer: PlanQuestionAnswer) {
        if let index = questionHistory.firstIndex(where: { $0.id == questionID }) {
            questionHistory[index].answer = answer
            questionHistory[index].status = .answered
            questionHistory[index].answeredAt = Date()
        }

        if let index = questionHistory.firstIndex(where: { $0.id == questionID && $0.status == .pending }) {
            questionHistory[index].status = .resolved
        }

        if currentQuestion?.id == questionID {
            currentQuestion = nil
        }

        answerContinuations[questionID]?.resume(returning: answer)
        answerContinuations.removeValue(forKey: questionID)
        persistQuestions()
    }

    public func cancel(questionID: UUID) {
        if let index = questionHistory.firstIndex(where: { $0.id == questionID }) {
            questionHistory[index].status = .cancelled
        }
        if currentQuestion?.id == questionID {
            currentQuestion = nil
        }
        answerContinuations[questionID]?.resume(returning: nil)
        answerContinuations.removeValue(forKey: questionID)
        persistQuestions()
    }

    public func restoreFromPersistence() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let questions = try? JSONDecoder().decode([PlanQuestion].self, from: data) else {
            return
        }
        questionHistory = questions
        if let pending = questions.first(where: { $0.status == .pending }) {
            currentQuestion = pending
        }
    }

    private func persistQuestions() {
        if let data = try? JSONEncoder().encode(questionHistory) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
}
