// Ported from Legacy `SwiftCode/Frameworks/Diff/MyersDiffAlgorithm.swift` (commit d51a8f0d, Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See _fragments/reverse-diff-MANIFEST.md.
// NOTE: only `LiveEditOperationType` and `LiveFileEditEvent` are ported from
// this file. `MyersDiffAlgorithm` itself is skipped — already ported as
// `MyersDiff` in swiftcode/Sources/SwiftCodeIDECore/MyersDiff.swift.
// `LiveDiffStreamer` is skipped per docs/ma-reconciliation.md (listed as
// matched in SwiftCodeMCP); the destination comment there states it was
// deliberately NOT ported (no unreviewed side writes), so the skip aligns
// with destination intent.
// `DiffHunk` (used by `LiveFileEditEvent.hunks`) is staged in
// `SwiftCodeIDECore/DiffHunk.swift`, ported from Legacy
// `SwiftCode/Backend/Assist/AssistDiffEngine.swift` — see
// _notes/agent-models-decisions.md.

import Foundation

public enum LiveEditOperationType: String, Codable, Sendable {
    case write = "write"
    case replace = "replace"
    case insert = "insert"
    case append = "append"
    case create = "create"
    case delete = "delete"
}

public struct LiveFileEditEvent: Identifiable, Sendable, Codable {
    public let id: UUID
    public let sessionId: String
    public let taskId: String
    public let goalId: String
    public let filePath: String
    public let operationId: String
    public let operationType: LiveEditOperationType
    public let timestamp: Date
    public var sequenceNumber: Int
    public let beforeContent: String
    public var currentContent: String
    public var hunks: [DiffHunk]
    public var addedLineCount: Int
    public var deletedLineCount: Int
    public var isFinal: Bool
    public var isReconciled: Bool

    public init(
        id: UUID = UUID(),
        sessionId: String = UUID().uuidString,
        taskId: String = "active_task",
        goalId: String = "active_goal",
        filePath: String,
        operationId: String = UUID().uuidString,
        operationType: LiveEditOperationType,
        timestamp: Date = Date(),
        sequenceNumber: Int = 1,
        beforeContent: String,
        currentContent: String,
        hunks: [DiffHunk] = [],
        addedLineCount: Int = 0,
        deletedLineCount: Int = 0,
        isFinal: Bool = false,
        isReconciled: Bool = false
    ) {
        self.id = id
        self.sessionId = sessionId
        self.taskId = taskId
        self.goalId = goalId
        self.filePath = filePath
        self.operationId = operationId
        self.operationType = operationType
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
        self.beforeContent = beforeContent
        self.currentContent = currentContent
        self.hunks = hunks
        self.addedLineCount = addedLineCount
        self.deletedLineCount = deletedLineCount
        self.isFinal = isFinal
        self.isReconciled = isReconciled
    }
}
