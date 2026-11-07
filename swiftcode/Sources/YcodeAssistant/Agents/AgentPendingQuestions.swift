import Foundation

public struct AgentPendingQuestion: Identifiable, Codable, Sendable {
    public let id: UUID
    public let question: String
    public let inputType: InputType

    public enum InputType: Codable, Sendable {
        case text
        case selection(options: [String])
    }

    public init(id: UUID = UUID(), question: String, inputType: InputType) {
        self.id = id
        self.question = question
        self.inputType = inputType
    }
}

public struct AgentPendingQuestionSet: Identifiable, Codable, Sendable {
    public let id: UUID
    public let questions: [AgentPendingQuestion]

    public init(id: UUID = UUID(), questions: [AgentPendingQuestion]) {
        self.id = id
        self.questions = questions
    }
}

public actor PendingQuestionStore {
    public static let shared = PendingQuestionStore()

    public struct PendingEntry: Sendable {
        public let question: AgentPendingQuestion
        public let allowsMultipleAnswers: Bool
        public let userSpecification: Bool
    }

    public struct PendingSetEntry: Sendable {
        public let set: AgentPendingQuestionSet
    }

    private var pending: [UUID: PendingEntry] = [:]
    private var pendingSets: [UUID: PendingSetEntry] = [:]
    private var answers: [UUID: String] = [:]
    private var setAnswers: [UUID: [UUID: String]] = [:]
    private var waiters: [UUID: [CheckedContinuation<String, Error>]] = [:]
    private var setWaiters: [UUID: [CheckedContinuation<[UUID: String], Error>]] = [:]

    public init() {}

    public func register(_ question: AgentPendingQuestion, allowsMultipleAnswers: Bool = false, userSpecification: Bool = false) {
        pending[question.id] = PendingEntry(question: question, allowsMultipleAnswers: allowsMultipleAnswers, userSpecification: userSpecification)
    }

    public func registerSet(_ set: AgentPendingQuestionSet) {
        pendingSets[set.id] = PendingSetEntry(set: set)
    }

    public func pendingQuestion(id: UUID) -> PendingEntry? { pending[id] }
    public func pendingSet(id: UUID) -> PendingSetEntry? { pendingSets[id] }
    public var pendingQuestionIDs: [UUID] { Array(pending.keys) }
    public var pendingSetIDs: [UUID] { Array(pendingSets.keys) }

    public func awaitAnswer(questionId: UUID) async throws -> String {
        if let answer = answers[questionId] { return answer }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            waiters[questionId, default: []].append(continuation)
        }
    }

    public func awaitAnswers(setId: UUID) async throws -> [UUID: String] {
        if let answered = setAnswers[setId] { return answered }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UUID: String], Error>) in
            setWaiters[setId, default: []].append(continuation)
        }
    }

    public func submitAnswer(questionId: UUID, answer: String) {
        answers[questionId] = answer
        pending.removeValue(forKey: questionId)
        for continuation in waiters.removeValue(forKey: questionId) ?? [] {
            continuation.resume(returning: answer)
        }
    }

    public func submitAnswers(setId: UUID, answers: [UUID: String]) {
        setAnswers[setId] = answers
        for (questionId, answer) in answers {
            self.answers[questionId] = answer
            pending.removeValue(forKey: questionId)
            for continuation in waiters.removeValue(forKey: questionId) ?? [] {
                continuation.resume(returning: answer)
            }
        }
        pendingSets.removeValue(forKey: setId)
        for continuation in setWaiters.removeValue(forKey: setId) ?? [] {
            continuation.resume(returning: answers)
        }
    }

    public func cancel(questionId: UUID) {
        pending.removeValue(forKey: questionId)
        for continuation in waiters.removeValue(forKey: questionId) ?? [] {
            continuation.resume(throwing: CancellationError())
        }
    }

    public func cancelSet(setId: UUID) {
        pendingSets.removeValue(forKey: setId)
        for continuation in setWaiters.removeValue(forKey: setId) ?? [] {
            continuation.resume(throwing: CancellationError())
        }
    }
}
