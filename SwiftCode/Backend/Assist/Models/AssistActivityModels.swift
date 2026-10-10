import Foundation

/// Activity status for execution items inside the Assist Activity disclosure panel.
public enum ActivityStatus: String, Codable, Sendable {
    case pending = "Pending"
    case running = "Running"
    case retrying = "Retrying"
    case completed = "Completed"
    case failed = "Failed"
    case skipped = "Skipped"
    case cancelled = "Cancelled"

    public var iconName: String {
        switch self {
        case .pending: return "clock"
        case .running: return "ellipsis.circle"
        case .retrying: return "arrow.counterclockwise.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "slash.circle"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

/// Structured operation state model for tracking explicit lifecycle transitions.
public enum AssistOperationState: Codable, Sendable, Equatable {
    case pending
    case running
    case retrying(attempt: Int)
    case completed
    case failed(reason: String)
    case cancelled

    public var activityStatus: ActivityStatus {
        switch self {
        case .pending: return .pending
        case .running: return .running
        case .retrying: return .retrying
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }
}

/// Tool activity item representing logical tool execution inside Activity disclosure.
public struct ToolActivityItem: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public let toolId: String
    public var purpose: String
    public var result: String
    public var status: ActivityStatus
    public var duration: TimeInterval
    public var timestamp: Date
    public var displayLabel: String?
    public var completedLabel: String?
    public var iconName: String?
    public var attemptsCount: Int
    public var retryCount: Int
    public var semanticKey: String?
    public var operationId: String?

    public init(
        id: UUID = UUID(),
        toolId: String,
        purpose: String,
        result: String = "",
        status: ActivityStatus = .completed,
        duration: TimeInterval = 0.0,
        timestamp: Date = Date(),
        displayLabel: String? = nil,
        completedLabel: String? = nil,
        iconName: String? = nil,
        attemptsCount: Int = 1,
        retryCount: Int = 0,
        semanticKey: String? = nil,
        operationId: String? = nil
    ) {
        self.id = id
        self.toolId = toolId
        self.purpose = purpose
        self.result = result
        self.status = status
        self.duration = duration
        self.timestamp = timestamp
        self.displayLabel = displayLabel
        self.completedLabel = completedLabel
        self.iconName = iconName
        self.attemptsCount = attemptsCount
        self.retryCount = retryCount
        self.semanticKey = semanticKey
        self.operationId = operationId
    }
}

/// File modification item with Myers diff line statistics and hunks.
public struct FileActivityItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let filePath: String
    public let operation: String // "Created", "Modified", "Deleted", "Renamed", "Moved"
    public var addedLines: Int
    public var deletedLines: Int
    public var diffSummary: String?
    public var diffHunks: [String]
    public var isReconciled: Bool

    public init(
        id: UUID = UUID(),
        filePath: String,
        operation: String = "Modified",
        addedLines: Int = 0,
        deletedLines: Int = 0,
        diffSummary: String? = nil,
        diffHunks: [String] = [],
        isReconciled: Bool = true
    ) {
        self.id = id
        self.filePath = filePath
        self.operation = operation
        self.addedLines = addedLines
        self.deletedLines = deletedLines
        self.diffSummary = diffSummary
        self.diffHunks = diffHunks
        self.isReconciled = isReconciled
    }

    public var changeDescription: String {
        if addedLines == 0 && deletedLines == 0 { return "No changes" }
        var parts: [String] = []
        if addedLines > 0 { parts.append("+\(addedLines)") }
        if deletedLines > 0 { parts.append("−\(deletedLines)") }
        return parts.joined(separator: " ")
    }

    public var hasChanges: Bool {
        return addedLines > 0 || deletedLines > 0
    }
}

/// Terminal activity item for raw or structured terminal execution inside Activity.
public struct TerminalActivityItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let command: String
    public let workingDirectory: String
    public var output: String
    public var exitCode: Int32?
    public var status: ActivityStatus
    public let timestamp: Date
    public var attemptsCount: Int

    public init(
        id: UUID = UUID(),
        command: String,
        workingDirectory: String = ".",
        output: String = "",
        exitCode: Int32? = nil,
        status: ActivityStatus = .completed,
        timestamp: Date = Date(),
        attemptsCount: Int = 1
    ) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.output = output
        self.exitCode = exitCode
        self.status = status
        self.timestamp = timestamp
        self.attemptsCount = attemptsCount
    }
}

/// Build activity item detailing xcodebuild or compilation status.
public struct BuildActivityItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let scheme: String?
    public var status: ActivityStatus
    public var errorCount: Int
    public var warningCount: Int
    public var diagnostics: [String]
    public var duration: TimeInterval
    public let timestamp: Date
    public var attemptsCount: Int

    public init(
        id: UUID = UUID(),
        scheme: String? = nil,
        status: ActivityStatus = .completed,
        errorCount: Int = 0,
        warningCount: Int = 0,
        diagnostics: [String] = [],
        duration: TimeInterval = 0.0,
        timestamp: Date = Date(),
        attemptsCount: Int = 1
    ) {
        self.id = id
        self.scheme = scheme
        self.status = status
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.diagnostics = diagnostics
        self.duration = duration
        self.timestamp = timestamp
        self.attemptsCount = attemptsCount
    }
}

/// Test execution activity item inside Activity panel.
public struct TestActivityItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let suiteName: String
    public var passedCount: Int
    public var failedCount: Int
    public var skippedCount: Int
    public var failureDetails: [String]
    public var status: ActivityStatus
    public var duration: TimeInterval
    public let timestamp: Date
    public var attemptsCount: Int

    public init(
        id: UUID = UUID(),
        suiteName: String = "Test Suite",
        passedCount: Int = 0,
        failedCount: Int = 0,
        skippedCount: Int = 0,
        failureDetails: [String] = [],
        status: ActivityStatus = .completed,
        duration: TimeInterval = 0.0,
        timestamp: Date = Date(),
        attemptsCount: Int = 1
    ) {
        self.id = id
        self.suiteName = suiteName
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.failureDetails = failureDetails
        self.status = status
        self.duration = duration
        self.timestamp = timestamp
        self.attemptsCount = attemptsCount
    }
}

/// Subagent / Worker execution activity item inside Activity disclosure.
public struct WorkerActivityItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let workerId: String
    public let name: String
    public let role: String
    public let scope: String
    public var taskDescription: String
    public var status: ActivityStatus
    public var progress: Double
    public var userFacingTitle: String

    public init(
        id: UUID = UUID(),
        workerId: String,
        name: String,
        role: String = "Subagent",
        scope: String = "Workspace",
        taskDescription: String = "",
        status: ActivityStatus = .running,
        progress: Double = 0.0,
        userFacingTitle: String? = nil
    ) {
        self.id = id
        self.workerId = workerId
        self.name = name
        self.role = role
        self.scope = scope
        self.taskDescription = taskDescription
        self.status = status
        self.progress = progress

        if let title = userFacingTitle, !title.isEmpty {
            self.userFacingTitle = title
        } else {
            let cleanName = name.replacingOccurrences(of: "start_subagent", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.userFacingTitle = cleanName.isEmpty ? "Worker" : "Worker · \(cleanName)"
        }
    }
}

/// Recoverable or unrecoverable error & recovery strategy activity item.
public struct RecoveryActivityItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let domain: String // "Tool", "Model", "Build", "Test", "Worker", "File", "Context"
    public let failureReason: String
    public let strategy: String
    public var attemptNumber: Int
    public var maxAttempts: Int
    public var isResolved: Bool
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        domain: String,
        failureReason: String,
        strategy: String,
        attemptNumber: Int = 1,
        maxAttempts: Int = 5,
        isResolved: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.domain = domain
        self.failureReason = failureReason
        self.strategy = strategy
        self.attemptNumber = attemptNumber
        self.maxAttempts = maxAttempts
        self.isResolved = isResolved
        self.timestamp = timestamp
    }
}

/// Verification check activity item inside Activity disclosure.
public struct VerificationActivityItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let checkName: String
    public var isPassed: Bool
    public var details: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        checkName: String,
        isPassed: Bool = true,
        details: String = "Passed baseline check",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.checkName = checkName
        self.isPassed = isPassed
        self.details = details
        self.timestamp = timestamp
    }
}

/// Aggregated technical activity group associated with an Assist conversational message.
public struct AssistActivityGroup: Codable, Identifiable, Sendable {
    public let id: UUID
    public var tools: [ToolActivityItem]
    public var files: [FileActivityItem]
    public var terminalCommands: [TerminalActivityItem]
    public var builds: [BuildActivityItem]
    public var tests: [TestActivityItem]
    public var workers: [WorkerActivityItem]
    public var recoveries: [RecoveryActivityItem]
    public var verifications: [VerificationActivityItem]
    public var isExecuting: Bool

    public init(
        id: UUID = UUID(),
        tools: [ToolActivityItem] = [],
        files: [FileActivityItem] = [],
        terminalCommands: [TerminalActivityItem] = [],
        builds: [BuildActivityItem] = [],
        tests: [TestActivityItem] = [],
        workers: [WorkerActivityItem] = [],
        recoveries: [RecoveryActivityItem] = [],
        verifications: [VerificationActivityItem] = [],
        isExecuting: Bool = false
    ) {
        self.id = id
        self.tools = tools
        self.files = files
        self.terminalCommands = terminalCommands
        self.builds = builds
        self.tests = tests
        self.workers = workers
        self.recoveries = recoveries
        self.verifications = verifications
        self.isExecuting = isExecuting
    }

    /// Whether there is any non-empty activity content to show.
    public var hasContent: Bool {
        return !tools.isEmpty ||
               !files.isEmpty ||
               !terminalCommands.isEmpty ||
               !builds.isEmpty ||
               !tests.isEmpty ||
               !workers.isEmpty ||
               !recoveries.isEmpty ||
               !verifications.isEmpty
    }

    /// Total count of primary technical actions performed.
    public var totalActionsCount: Int {
        return tools.count + terminalCommands.count + builds.count + tests.count + verifications.count
    }

    /// Compact summary string formatted according to section 9 of spec.
    public var collapsedSummary: String {
        if !recoveries.isEmpty {
            let resolvedCount = recoveries.filter { $0.isResolved }.count
            return "Recovered from \(resolvedCount) error\(resolvedCount == 1 ? "" : "s")"
        }
        if !workers.isEmpty {
            return "\(workers.count) Worker\(workers.count == 1 ? "" : "s") · \(totalActionsCount) action\(totalActionsCount == 1 ? "" : "s")"
        }
        if let lastBuild = builds.last {
            return lastBuild.status == .completed ? "Build succeeded" : "Build failed (\(lastBuild.errorCount) errors)"
        }
        if let lastTest = tests.last {
            return "\(lastTest.passedCount) test\(lastTest.passedCount == 1 ? "" : "s") passed"
        }
        if !files.isEmpty {
            return "\(files.count) file\(files.count == 1 ? "" : "s") changed"
        }
        if totalActionsCount > 0 {
            return "\(totalActionsCount) action\(totalActionsCount == 1 ? "" : "s")"
        }
        return "Activity"
    }
}
