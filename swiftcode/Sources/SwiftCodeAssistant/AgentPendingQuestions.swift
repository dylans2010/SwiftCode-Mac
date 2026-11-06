import Foundation

/// A question the agent asks the user mid-turn (Legacy
/// `SwiftCode/Core/AI/Agent/AgentPendingQuestion.swift`, Dylan's own code,
/// ported under MIT).
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

/// A set of questions submitted together (Legacy
/// `AgentPendingQuestionSet.swift`).
public struct AgentPendingQuestionSet: Identifiable, Codable, Sendable {
    public let id: UUID
    public let questions: [AgentPendingQuestion]

    public init(id: UUID = UUID(), questions: [AgentPendingQuestion]) {
        self.id = id
        self.questions = questions
    }
}

/// The stored pending-question state the destination was missing:
/// `plan-AskUser` returned a `questionId` but never blocked and kept
/// no answer flow. This store holds the pending question (or set)
/// and the turn resumes when `submitAnswer` / `submitAnswers` is
/// called — `awaitAnswer` suspends the agent turn until then.
///
/// Wiring: `SwiftCodeMCPHost.askUser` registers each question it
/// returns here (see the patched `SwiftCodeTools+Planning.swift`);
/// the IDE's question UI calls `submitAnswer(questionId:answer:)` (or
/// `submitAnswers` for a set) when the user replies. An agent turn
/// awaiting an answer suspends on `awaitAnswer(questionId:)` and
/// resumes with the answer; cancelling the turn calls `cancel`
/// instead so the waiter resumes with a cancellation rather than
/// hanging. `AgentTurnState.awaitingUserAnswer` is the matching
/// session state.
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

    /// Suspends until the user answers `id` (or the turn is
    /// cancelled). Returns the answer text.
    public func awaitAnswer(questionId: UUID) async throws -> String {
        if let answer = answers[questionId] { return answer }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            waiters[questionId, default: []].append(continuation)
        }
    }

    /// Suspends until the user answers every question of set `id`.
    /// Returns one answer per question id.
    public func awaitAnswers(setId: UUID) async throws -> [UUID: String] {
        if let answered = setAnswers[setId] { return answered }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UUID: String], Error>) in
            setWaiters[setId, default: []].append(continuation)
        }
    }

    /// The user's answer to one pending question. Resumes any waiter
    /// and removes the question from the pending list.
    public func submitAnswer(questionId: UUID, answer: String) {
        answers[questionId] = answer
        pending.removeValue(forKey: questionId)
        for continuation in waiters.removeValue(forKey: questionId) ?? [] {
            continuation.resume(returning: answer)
        }
    }

    /// The user's answers to a whole question set, keyed by question id.
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

    /// The turn was cancelled while waiting: every waiter for `id`
    /// resumes with a cancellation instead of hanging.
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
