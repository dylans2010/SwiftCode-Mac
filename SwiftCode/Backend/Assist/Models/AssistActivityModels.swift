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

    /// Whether this status represents an active, non-terminal state.
    public var isRunning: Bool {
        return self == .running || self == .retrying
    }

    /// Whether this status represents a terminal state.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .skipped, .cancelled:
            return true
        case .pending, .running, .retrying:
            return false
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
    case timedOut(duration: TimeInterval? = nil)

    public var activityStatus: ActivityStatus {
        switch self {
        case .pending: return .pending
        case .running: return .running
        case .retrying: return .retrying
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .timedOut: return .failed
        }
    }
}

/// Tool activity item representing logical tool execution inside Activity disclosure.
public struct ToolActivityItem: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var callId: String
    public let toolId: String
    public var purpose: String
    public var argumentsSummary: String
    public var streamingOutput: String
    public var result: String
    public var status: ActivityStatus
    public var progress: Double?
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
        callId: String? = nil,
        toolId: String,
        purpose: String,
        argumentsSummary: String = "",
        streamingOutput: String = "",
        result: String = "",
        status: ActivityStatus = .completed,
        progress: Double? = nil,
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
        let resolvedCallId = callId ?? operationId ?? id.uuidString
        self.callId = resolvedCallId
        self.toolId = toolId
        self.purpose = purpose
        self.argumentsSummary = argumentsSummary
        self.streamingOutput = streamingOutput
        self.result = result
        self.status = status
        self.progress = progress
        self.duration = duration
        self.timestamp = timestamp
        self.displayLabel = displayLabel
        self.completedLabel = completedLabel
        self.iconName = iconName
        self.attemptsCount = attemptsCount
        self.retryCount = retryCount
        self.semanticKey = semanticKey
        self.operationId = operationId ?? resolvedCallId
    }

    enum CodingKeys: String, CodingKey {
        case id, callId, toolId, purpose, argumentsSummary, streamingOutput
        case result, status, progress, duration, timestamp
        case displayLabel, completedLabel, iconName, attemptsCount, retryCount
        case semanticKey, operationId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.id = decodedId
        let decodedCallId = try container.decodeIfPresent(String.self, forKey: .callId)
        let decodedOpId = try container.decodeIfPresent(String.self, forKey: .operationId)
        let resolvedCallId = decodedCallId ?? decodedOpId ?? decodedId.uuidString
        self.callId = resolvedCallId
        self.toolId = try container.decodeIfPresent(String.self, forKey: .toolId) ?? ""
        self.purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        self.argumentsSummary = try container.decodeIfPresent(String.self, forKey: .argumentsSummary) ?? ""
        self.streamingOutput = try container.decodeIfPresent(String.self, forKey: .streamingOutput) ?? ""
        self.result = try container.decodeIfPresent(String.self, forKey: .result) ?? ""
        self.status = try container.decodeIfPresent(ActivityStatus.self, forKey: .status) ?? .completed
        self.progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        self.duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0.0
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.displayLabel = try container.decodeIfPresent(String.self, forKey: .displayLabel)
        self.completedLabel = try container.decodeIfPresent(String.self, forKey: .completedLabel)
        self.iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        self.attemptsCount = try container.decodeIfPresent(Int.self, forKey: .attemptsCount) ?? 1
        self.retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        self.semanticKey = try container.decodeIfPresent(String.self, forKey: .semanticKey)
        self.operationId = decodedOpId ?? resolvedCallId
    }

    // MARK: - Computed Properties

    /// Clean display output that presents the final result or streaming output,
    /// filtering out raw JSON envelopes.
    public var displayOutput: String {
        let raw: String
        if status == .running || status == .retrying {
            raw = !streamingOutput.isEmpty ? streamingOutput : result
        } else {
            raw = !result.isEmpty ? result : streamingOutput
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.contains("\"toolId\"") {
            return ""
        }
        return trimmed
    }

    /// Whether this item has non-empty output to show.
    public var hasOutput: Bool {
        return !displayOutput.isEmpty
    }

    /// Whether the tool is currently running or retrying.
    public var isRunning: Bool {
        return status.isRunning
    }

    /// Whether the tool reached a final, terminal status.
    public var isTerminal: Bool {
        return status.isTerminal
    }

    /// Formatted elapsed duration string (e.g. "0.4s").
    public var formattedDuration: String {
        return duration > 0 ? String(format: "%.1fs", duration) : ""
    }

    /// Progress expressed as a percentage integer (0–100) if available.
    public var progressPercentage: Int? {
        return progress.map { Int(($0 * 100.0).rounded()) }
    }

    /// Checks whether this activity matches the given call identifiers.
    public func matches(callId: String?, operationId: String? = nil, uuid: UUID? = nil) -> Bool {
        if let uuid = uuid, self.id == uuid {
            return true
        }
        if let callId = callId, !callId.isEmpty {
            if self.callId == callId || self.operationId == callId {
                return true
            }
        }
        if let opId = operationId, !opId.isEmpty {
            if self.operationId == opId || self.callId == opId {
                return true
            }
        }
        return false
    }

    // MARK: - Mutation & Lifecycle Methods

    /// Appends an incremental chunk of streamed output.
    public mutating func appendStreamingChunk(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        streamingOutput.append(chunk)
    }

    /// Updates progress value (0.0 to 1.0) and optionally updates status/result message.
    public mutating func updateProgress(progress: Double? = nil, message: String? = nil) {
        if let progress = progress {
            self.progress = min(max(progress, 0.0), 1.0)
        }
        if let message = message, !message.isEmpty {
            self.result = message
        }
    }

    /// Marks the item as started or actively running.
    public mutating func markStarted(label: String? = nil) {
        self.status = .running
        if let label = label, !label.isEmpty {
            self.purpose = label
            self.displayLabel = label
        }
    }

    /// Marks the item as retrying, incrementing attempt and retry counters.
    public mutating func markRetrying(attempt: Int? = nil, label: String? = nil) {
        self.status = .retrying
        self.retryCount = attempt ?? (self.retryCount + 1)
        self.attemptsCount = self.retryCount + 1
        self.timestamp = Date()
        self.duration = 0
        if let label = label {
            self.purpose = label
        } else if let display = displayLabel {
            self.purpose = "\(display) (Retry \(self.retryCount + 1))"
        }
    }

    /// Marks the item as successfully completed.
    public mutating func markCompleted(output: String? = nil, duration: TimeInterval? = nil) {
        self.status = .completed
        if let output = output, !output.isEmpty {
            self.result = output
        } else if self.result.isEmpty && !self.streamingOutput.isEmpty {
            self.result = self.streamingOutput
        }
        if let duration = duration {
            self.duration = max(0.01, duration)
        } else if self.duration <= 0 {
            self.duration = max(0.01, Date().timeIntervalSince(self.timestamp))
        }
        if let completedLabel = self.completedLabel {
            self.purpose = completedLabel
        }
        self.progress = 1.0
    }

    /// Marks the item as failed with an error reason.
    public mutating func markFailed(error: String, duration: TimeInterval? = nil) {
        self.status = .failed
        self.result = error
        if let duration = duration {
            self.duration = max(0.01, duration)
        } else if self.duration <= 0 {
            self.duration = max(0.01, Date().timeIntervalSince(self.timestamp))
        }
        let base = self.displayLabel ?? self.purpose
        self.purpose = "\(base) — \(error)"
    }

    /// Marks the item as cancelled.
    public mutating func markCancelled(reason: String = "Cancelled", duration: TimeInterval? = nil) {
        self.status = .cancelled
        self.result = reason
        if let duration = duration {
            self.duration = max(0.01, duration)
        } else if self.duration <= 0 {
            self.duration = max(0.01, Date().timeIntervalSince(self.timestamp))
        }
        let base = self.displayLabel ?? self.purpose
        self.purpose = "\(base) (Cancelled)"
    }

    /// Marks the item as timed out.
    public mutating func markTimedOut(duration: TimeInterval? = nil) {
        self.status = .failed
        self.result = "Operation timed out waiting for tool/runtime progress"
        if let duration = duration {
            self.duration = max(0.01, duration)
        } else if self.duration <= 0 {
            self.duration = max(0.01, Date().timeIntervalSince(self.timestamp))
        }
        let base = self.displayLabel ?? self.purpose
        self.purpose = "\(base) (Timed Out)"
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

    // MARK: - Lifecycle & Progress Helpers

    /// Whether there are any active operations currently running or retrying.
    public var hasRunningOperations: Bool {
        return tools.contains(where: { $0.isRunning }) ||
               terminalCommands.contains(where: { $0.status == .running || $0.status == .retrying }) ||
               builds.contains(where: { $0.status == .running || $0.status == .retrying }) ||
               tests.contains(where: { $0.status == .running || $0.status == .retrying }) ||
               workers.contains(where: { $0.status == .running || $0.status == .retrying })
    }

    /// Synchronizes `isExecuting` with the actual operational state.
    public mutating func refreshExecutingState() {
        self.isExecuting = hasRunningOperations
    }

    /// Finds a tool activity item by callId or operationId.
    public func tool(forCallId callId: String) -> ToolActivityItem? {
        return tools.first(where: { $0.matches(callId: callId) })
    }

    /// Appends a streaming output chunk to the matching tool activity item.
    public mutating func appendOutputChunk(callId: String, chunk: String) {
        guard !chunk.isEmpty else { return }
        if let idx = tools.firstIndex(where: { $0.matches(callId: callId) }) {
            tools[idx].appendStreamingChunk(chunk)
        }
    }

    /// Updates progress on the matching tool activity item.
    public mutating func updateToolProgress(callId: String, progress: Double? = nil, message: String? = nil) {
        if let idx = tools.firstIndex(where: { $0.matches(callId: callId) }) {
            tools[idx].updateProgress(progress: progress, message: message)
        }
    }

    /// Finalizes all running or retrying operations cleanly so nothing is left stuck in a running state.
    public mutating func finalizeAllRunningOperations(status: ActivityStatus = .cancelled, reason: String? = nil) {
        let finalReason = reason ?? (status == .cancelled ? "Operation cancelled" : (status == .failed ? "Operation timed out" : status.rawValue))
        let now = Date()

        for idx in tools.indices where tools[idx].isRunning {
            tools[idx].status = status
            if tools[idx].result.isEmpty {
                tools[idx].result = finalReason
            }
            if tools[idx].duration <= 0 {
                tools[idx].duration = max(0.1, now.timeIntervalSince(tools[idx].timestamp))
            }
            let label = tools[idx].completedLabel ?? tools[idx].displayLabel ?? tools[idx].purpose
            tools[idx].purpose = "\(label) (\(status.rawValue))"
        }

        for idx in workers.indices where workers[idx].status == .running || workers[idx].status == .retrying {
            workers[idx].status = status
            workers[idx].taskDescription = finalReason
        }

        for idx in terminalCommands.indices where terminalCommands[idx].status == .running || terminalCommands[idx].status == .retrying {
            terminalCommands[idx].status = status
            if terminalCommands[idx].output.isEmpty {
                terminalCommands[idx].output = finalReason
            }
        }

        for idx in builds.indices where builds[idx].status == .running || builds[idx].status == .retrying {
            builds[idx].status = status
            if builds[idx].duration <= 0 {
                builds[idx].duration = max(0.1, now.timeIntervalSince(builds[idx].timestamp))
            }
            if status == .failed {
                builds[idx].errorCount = max(1, builds[idx].errorCount)
            }
        }

        for idx in tests.indices where tests[idx].status == .running || tests[idx].status == .retrying {
            tests[idx].status = status
            if tests[idx].duration <= 0 {
                tests[idx].duration = max(0.1, now.timeIntervalSince(tests[idx].timestamp))
            }
            if status == .failed {
                tests[idx].failedCount = max(1, tests[idx].failedCount)
            }
        }

        self.isExecuting = false
    }
}
