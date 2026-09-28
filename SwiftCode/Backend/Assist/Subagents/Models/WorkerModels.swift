import Foundation

// MARK: - Worker Status & Lifecycle

public enum WorkerStatus: String, Codable, Sendable, CaseIterable {
    case created = "CREATED"
    case queued = "QUEUED"
    case assigned = "ASSIGNED"
    case starting = "STARTING"
    case working = "WORKING"
    case reviewing = "REVIEWING"
    case completed = "COMPLETED"
    case standby = "STANDBY"
    case reassigning = "REASSIGNING"
    case failed = "FAILED"
    case cancelled = "CANCELLED"
    case blocked = "BLOCKED"

    public var isActive: Bool {
        switch self {
        case .queued, .assigned, .starting, .working, .reviewing:
            return true
        default:
            return false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed:
            return true
        default:
            return false
        }
    }

    public var isWorking: Bool {
        self == .working
    }

    /// Distinct native SF Symbol for each state (No emoji allowed per INV-14)
    public var sfSymbolName: String {
        switch self {
        case .created:
            return "clock"
        case .queued:
            return "hourglass"
        case .assigned:
            return "person.badge.shield.checkmark"
        case .starting:
            return "rays"
        case .working:
            return "gearshape.arrow.triangle.2.circlepath"
        case .reviewing:
            return "eye.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .standby:
            return "pause.circle.fill"
        case .reassigning:
            return "arrow.triangle.2.circlepath.circle"
        case .failed:
            return "xmark.octagon.fill"
        case .cancelled:
            return "slash.circle.fill"
        case .blocked:
            return "exclamationmark.shield.fill"
        }
    }
}

// MARK: - Worker Phase

public enum WorkerPhase: String, Codable, Sendable {
    case implementation = "Implementation"
    case testing = "Testing"
    case verification = "Verification"
    case review = "Review"
}

// MARK: - Review State

public enum WorkerReviewState: String, Codable, Sendable {
    case notReviewed = "Not Reviewed"
    case reviewing = "Reviewing"
    case accepted = "Accepted"
    case rejected = "Rejected"
    case repairRequired = "Repair Required"

    public var sfSymbolName: String {
        switch self {
        case .notReviewed:
            return "circle.dashed"
        case .reviewing:
            return "magnifyingglass.circle"
        case .accepted:
            return "checkmark.shield.fill"
        case .rejected:
            return "xmark.shield.fill"
        case .repairRequired:
            return "wrench.and.screwdriver.fill"
        }
    }
}

// MARK: - File Changes

public enum FileChangeType: String, Codable, Sendable {
    case created = "Created"
    case modified = "Modified"
    case deleted = "Deleted"
    case renamed = "Renamed"

    public var sfSymbolName: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "trash.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        }
    }
}

public struct WorkerFileChange: Identifiable, Codable, Sendable, Hashable {
    public typealias ChangeType = FileChangeType
    public let id: UUID
    public let path: String
    public let changeType: FileChangeType
    public let previousPath: String?
    public let timestamp: Date
    public var linesAdded: Int
    public var linesRemoved: Int

    public init(
        id: UUID = UUID(),
        path: String,
        changeType: FileChangeType,
        previousPath: String? = nil,
        timestamp: Date = Date(),
        linesAdded: Int = 0,
        linesRemoved: Int = 0
    ) {
        self.id = id
        self.path = path
        self.changeType = changeType
        self.previousPath = previousPath
        self.timestamp = timestamp
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
    }

    public var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

// MARK: - Test Record

public struct WorkerTestRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let testName: String
    public let suite: String
    public let passed: Bool
    public let duration: TimeInterval
    public let output: String
    public let failureReason: String?

    public init(
        id: UUID = UUID(),
        testName: String,
        suite: String = "DefaultSuite",
        passed: Bool,
        duration: TimeInterval = 0.0,
        output: String = "",
        failureReason: String? = nil
    ) {
        self.id = id
        self.testName = testName
        self.suite = suite
        self.passed = passed
        self.duration = duration
        self.output = output
        self.failureReason = failureReason
    }
}

// MARK: - Worker Progress

public struct WorkerProgress: Codable, Sendable {
    public var narrative: String
    public var currentAction: String
    public var phase: WorkerPhase
    public var lastCompleted: String?
    public var discovered: String?
    public var nextPlan: String?
    public var percentage: Double?
    public var isBlocked: Bool
    public var blockReason: String?

    public init(
        narrative: String = "Initialized",
        currentAction: String = "Awaiting assignment",
        phase: WorkerPhase = .implementation,
        lastCompleted: String? = nil,
        discovered: String? = nil,
        nextPlan: String? = nil,
        percentage: Double? = nil,
        isBlocked: Bool = false,
        blockReason: String? = nil
    ) {
        self.narrative = narrative
        self.currentAction = currentAction
        self.phase = phase
        self.lastCompleted = lastCompleted
        self.discovered = discovered
        self.nextPlan = nextPlan
        self.percentage = percentage
        self.isBlocked = isBlocked
        self.blockReason = blockReason
    }
}

// MARK: - Worker Error

public struct WorkerError: Codable, Sendable {
    public let code: String
    public let message: String
    public let timestamp: Date
    public let recoverable: Bool
    public let rootCause: String?
    public let remedy: String?

    public var details: String? {
        rootCause ?? remedy
    }

    public init(
        code: String,
        message: String,
        timestamp: Date = Date(),
        recoverable: Bool = true,
        rootCause: String? = nil,
        remedy: String? = nil
    ) {
        self.code = code
        self.message = message
        self.timestamp = timestamp
        self.recoverable = recoverable
        self.rootCause = rootCause
        self.remedy = remedy
    }
}

// MARK: - Worker Assignment

public struct WorkerAssignment: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let scope: String
    public let task: String
    public let role: String
    public var dependencies: [String]
    public var targetFiles: [String]
    public var preferredModel: String?

    public init(
        id: UUID = UUID(),
        name: String,
        scope: String,
        task: String,
        role: String = "General Engineer",
        dependencies: [String] = [],
        targetFiles: [String] = [],
        preferredModel: String? = nil
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.task = String(task.prefix(500)) // Enforce <= 500 characters
        self.role = role
        self.dependencies = dependencies
        self.targetFiles = targetFiles
        self.preferredModel = preferredModel
    }
}

// MARK: - Worker Result

public struct WorkerResult: Codable, Sendable {
    public let workerID: UUID
    public let workerName: String
    public let summary: String
    public let completedWork: [String]
    public let modifiedFiles: [String]
    public let createdFiles: [String]
    public let deletedFiles: [String]
    public let tests: [WorkerTestRecord]
    public let buildResult: String
    public let verificationResult: String
    public let knownIssues: [String]
    public let remainingWork: [String]
    public let recommendedParentAction: String
    public var executionDuration: TimeInterval

    public init(
        workerID: UUID,
        workerName: String,
        summary: String,
        completedWork: [String] = [],
        modifiedFiles: [String] = [],
        createdFiles: [String] = [],
        deletedFiles: [String] = [],
        tests: [WorkerTestRecord] = [],
        buildResult: String = "Passed",
        verificationResult: String = "Verified",
        knownIssues: [String] = [],
        remainingWork: [String] = [],
        recommendedParentAction: String = "Accept and integrate",
        executionDuration: TimeInterval = 0.0
    ) {
        self.workerID = workerID
        self.workerName = workerName
        self.summary = summary
        self.completedWork = completedWork
        self.modifiedFiles = modifiedFiles
        self.createdFiles = createdFiles
        self.deletedFiles = deletedFiles
        self.tests = tests
        self.buildResult = buildResult
        self.verificationResult = verificationResult
        self.knownIssues = knownIssues
        self.remainingWork = remainingWork
        self.recommendedParentAction = recommendedParentAction
        self.executionDuration = executionDuration
    }
}

// MARK: - Worker Review

public struct WorkerReview: Identifiable, Codable, Sendable {
    public let id: UUID
    public let workerID: UUID
    public let reviewerModel: String
    public let timestamp: Date
    public var status: WorkerReviewState
    public var confidence: Double
    public var strengths: [String]
    public var issues: [String]
    public var recommendedFixes: [String]
    public var repairAssignment: WorkerAssignment?

    public init(
        id: UUID = UUID(),
        workerID: UUID,
        reviewerModel: String = "Parent Assist",
        timestamp: Date = Date(),
        status: WorkerReviewState = .notReviewed,
        confidence: Double = 1.0,
        strengths: [String] = [],
        issues: [String] = [],
        recommendedFixes: [String] = [],
        repairAssignment: WorkerAssignment? = nil
    ) {
        self.id = id
        self.workerID = workerID
        self.reviewerModel = reviewerModel
        self.timestamp = timestamp
        self.status = status
        self.confidence = confidence
        self.strengths = strengths
        self.issues = issues
        self.recommendedFixes = recommendedFixes
        self.repairAssignment = repairAssignment
    }
}

// MARK: - Worker Handoff & Cancellation

public typealias WorkerStopMode = WorkerHandoffMode

public enum WorkerHandoffMode: String, Codable, Sendable {
    case preserve = "preserve"
    case handoffToNewWorker = "handoff"

    public static var reassign: WorkerHandoffMode { .handoffToNewWorker }
}

public struct WorkerHandoff: Identifiable, Codable, Sendable {
    public let id: UUID
    public let originalWorkerID: UUID
    public let originalWorkerName: String
    public let parentTaskID: UUID
    public let reason: String
    public let mode: WorkerHandoffMode
    public var completedWork: [String]
    public var remainingScope: String
    public var remainingTask: String
    public var filesChanged: [String]
    public var testsCompleted: [String]
    public var knownProblems: [String]
    public var replacementWorkerID: UUID?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        originalWorkerID: UUID,
        originalWorkerName: String,
        parentTaskID: UUID,
        reason: String,
        mode: WorkerHandoffMode,
        completedWork: [String] = [],
        remainingScope: String = "",
        remainingTask: String = "",
        filesChanged: [String] = [],
        testsCompleted: [String] = [],
        knownProblems: [String] = [],
        replacementWorkerID: UUID? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.originalWorkerID = originalWorkerID
        self.originalWorkerName = originalWorkerName
        self.parentTaskID = parentTaskID
        self.reason = reason
        self.mode = mode
        self.completedWork = completedWork
        self.remainingScope = remainingScope
        self.remainingTask = remainingTask
        self.filesChanged = filesChanged
        self.testsCompleted = testsCompleted
        self.knownProblems = knownProblems
        self.replacementWorkerID = replacementWorkerID
        self.timestamp = timestamp
    }
}

public struct WorkerCancellation: Codable, Sendable {
    public let workerID: UUID
    public let timestamp: Date
    public let reason: String
    public let workPreserved: Bool

    public init(
        workerID: UUID,
        timestamp: Date = Date(),
        reason: String,
        workPreserved: Bool = true
    ) {
        self.workerID = workerID
        self.timestamp = timestamp
        self.reason = reason
        self.workPreserved = workPreserved
    }
}

public struct WorkerDependency: Codable, Sendable {
    public let workerID: UUID
    public let dependsOnWorkerID: UUID
    public var isSatisfied: Bool

    public init(workerID: UUID, dependsOnWorkerID: UUID, isSatisfied: Bool = false) {
        self.workerID = workerID
        self.dependsOnWorkerID = dependsOnWorkerID
        self.isSatisfied = isSatisfied
    }
}

// MARK: - Primary Worker Entity

public struct Worker: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var role: String
    public var scope: String
    public var task: String
    public var status: WorkerStatus
    public let createdAt: Date
    public var startedAt: Date?
    public var updatedAt: Date
    public var completedAt: Date?
    public var parentTaskID: UUID
    public var currentAction: String
    public var currentPhase: WorkerPhase
    public var progress: WorkerProgress
    public var modifiedFiles: [WorkerFileChange]
    public var createdFiles: [WorkerFileChange]
    public var deletedFiles: [WorkerFileChange]
    public var renamedFiles: [WorkerFileChange]
    public var testsRun: [WorkerTestRecord]
    public var verificationState: String
    public var reviewState: WorkerReviewState
    public var errorState: WorkerError?
    public var handoffState: WorkerHandoff?
    public var dependencies: [UUID]
    public var modelUsed: String
    public var skillsUsed: [String]
    public var recap: [String]
    public var eventHistory: [WorkerEvent]
    public var cancellationReason: String?
    public var result: WorkerResult?

    public init(
        id: UUID = UUID(),
        name: String,
        role: String = "General Engineer",
        scope: String,
        task: String,
        status: WorkerStatus = .created,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        parentTaskID: UUID,
        currentAction: String = "Created",
        currentPhase: WorkerPhase = .implementation,
        progress: WorkerProgress = WorkerProgress(),
        modifiedFiles: [WorkerFileChange] = [],
        createdFiles: [WorkerFileChange] = [],
        deletedFiles: [WorkerFileChange] = [],
        renamedFiles: [WorkerFileChange] = [],
        testsRun: [WorkerTestRecord] = [],
        verificationState: String = "Unverified",
        reviewState: WorkerReviewState = .notReviewed,
        errorState: WorkerError? = nil,
        handoffState: WorkerHandoff? = nil,
        dependencies: [UUID] = [],
        modelUsed: String = "",
        skillsUsed: [String] = [],
        recap: [String] = [],
        eventHistory: [WorkerEvent] = [],
        cancellationReason: String? = nil,
        result: WorkerResult? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.scope = scope
        self.task = String(task.prefix(500))
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.parentTaskID = parentTaskID
        self.currentAction = currentAction
        self.currentPhase = currentPhase
        self.progress = progress
        self.modifiedFiles = modifiedFiles
        self.createdFiles = createdFiles
        self.deletedFiles = deletedFiles
        self.renamedFiles = renamedFiles
        self.testsRun = testsRun
        self.verificationState = verificationState
        self.reviewState = reviewState
        self.errorState = errorState
        self.handoffState = handoffState
        self.dependencies = dependencies
        self.modelUsed = modelUsed
        self.skillsUsed = skillsUsed
        self.recap = recap
        self.eventHistory = eventHistory
        self.cancellationReason = cancellationReason
        self.result = result
    }

    /// All files affected by this worker
    public var allAffectedFiles: [String] {
        let set = Set(
            modifiedFiles.map { $0.path } +
            createdFiles.map { $0.path } +
            deletedFiles.map { $0.path } +
            renamedFiles.map { $0.path }
        )
        return Array(set).sorted()
    }

    public var fileChanges: [WorkerFileChange] {
        modifiedFiles + createdFiles + deletedFiles + renamedFiles
    }

    public var totalLinesAdded: Int {
        fileChanges.reduce(0) { $0 + $1.linesAdded }
    }

    public var totalLinesRemoved: Int {
        fileChanges.reduce(0) { $0 + $1.linesRemoved }
    }

    public var progressFraction: Double {
        progress.percentage ?? 0.0
    }
}
