import Foundation

public struct MyersDiffAlgorithm: Sendable {
    public static let shared = MyersDiffAlgorithm()

    public init() {}

    public enum DiffEdit: Equatable, Sendable {
        case keep(line: String)
        case delete(line: String)
        case insert(line: String)

        public var line: String {
            switch self {
            case .keep(let l), .delete(let l), .insert(let l):
                return l
            }
        }
    }

    public func computeEditScript(old: [String], new: [String]) -> [DiffEdit] {
        let n = old.count
        let m = new.count
        let maxD = n + m

        if n == 0 && m == 0 { return [] }
        if n == 0 { return new.map { .insert(line: $0) } }
        if m == 0 { return old.map { .delete(line: $0) } }

        let vSize = 2 * maxD + 1
        let offset = maxD

        var v = [Int](repeating: 0, count: vSize)
        var trace: [[Int]] = []

        var reachedEnd = false
        var endD = 0

        for d in 0...maxD {
            trace.append(v)
            var k = -d
            while k <= d {
                let kIndex = k + offset
                var x: Int

                if k == -d || (k != d && v[kIndex - 1] < v[kIndex + 1]) {
                    x = v[kIndex + 1]
                } else {
                    x = v[kIndex - 1] + 1
                }

                var y = x - k

                while x < n && y < m && old[x] == new[y] {
                    x += 1
                    y += 1
                }

                v[kIndex] = x

                if x >= n && y >= m {
                    reachedEnd = true
                    endD = d
                    break
                }
                k += 2
            }
            if reachedEnd { break }
        }

        var edits: [DiffEdit] = []
        var curX = n
        var curY = m

        for d in stride(from: endD, through: 1, by: -1) {
            let vPrev = trace[d]
            let k = curX - curY
            let kIndex = k + offset

            let prevK: Int
            if k == -d || (k != d && vPrev[kIndex - 1] < vPrev[kIndex + 1]) {
                prevK = k + 1
            } else {
                prevK = k - 1
            }

            let prevKIndex = prevK + offset
            let prevX = vPrev[prevKIndex]
            let prevY = prevX - prevK

            while curX > prevX && curY > prevY {
                curX -= 1
                curY -= 1
                edits.append(.keep(line: old[curX]))
            }

            if d > 0 {
                if curX == prevX {
                    curY -= 1
                    edits.append(.insert(line: new[curY]))
                } else {
                    curX -= 1
                    edits.append(.delete(line: old[curX]))
                }
            }
        }

        while curX > 0 && curY > 0 {
            curX -= 1
            curY -= 1
            edits.append(.keep(line: old[curX]))
        }

        return edits.reversed()
    }

    public func computeUnifiedHunks(old: [String], new: [String], contextLines: Int = 3) -> [DiffHunk] {
        let edits = computeEditScript(old: old, new: new)
        if edits.isEmpty { return [] }

        let hasChanges = edits.contains { edit in
            if case .keep = edit { return false }
            return true
        }
        if !hasChanges { return [] }

        struct IndexedEdit {
            let edit: DiffEdit
            let oldLineNum: Int?
            let newLineNum: Int?
        }

        var indexed: [IndexedEdit] = []
        var oldLine = 1
        var newLine = 1

        for edit in edits {
            switch edit {
            case .keep:
                indexed.append(IndexedEdit(edit: edit, oldLineNum: oldLine, newLineNum: newLine))
                oldLine += 1
                newLine += 1
            case .delete:
                indexed.append(IndexedEdit(edit: edit, oldLineNum: oldLine, newLineNum: nil))
                oldLine += 1
            case .insert:
                indexed.append(IndexedEdit(edit: edit, oldLineNum: nil, newLineNum: newLine))
                newLine += 1
            }
        }

        var changeIndices: [Int] = []
        for (idx, item) in indexed.enumerated() {
            if case .keep = item.edit {} else {
                changeIndices.append(idx)
            }
        }

        if changeIndices.isEmpty { return [] }

        var hunkRanges: [ClosedRange<Int>] = []
        var currentRangeStart = max(0, changeIndices[0] - contextLines)
        var currentRangeEnd = min(indexed.count - 1, changeIndices[0] + contextLines)

        for idx in changeIndices.dropFirst() {
            let nextStart = max(0, idx - contextLines)
            let nextEnd = min(indexed.count - 1, idx + contextLines)

            if nextStart <= currentRangeEnd + 1 {
                currentRangeEnd = max(currentRangeEnd, nextEnd)
            } else {
                hunkRanges.append(currentRangeStart...currentRangeEnd)
                currentRangeStart = nextStart
                currentRangeEnd = nextEnd
            }
        }
        hunkRanges.append(currentRangeStart...currentRangeEnd)

        var hunks: [DiffHunk] = []

        for range in hunkRanges {
            var hunkLines: [String] = []
            var oldStart = 0
            var newStart = 0
            var oldCount = 0
            var newCount = 0

            var firstOld: Int?
            var firstNew: Int?

            for i in range {
                let item = indexed[i]
                switch item.edit {
                case .keep(let line):
                    hunkLines.append(" " + line)
                    if firstOld == nil { firstOld = item.oldLineNum }
                    if firstNew == nil { firstNew = item.newLineNum }
                    oldCount += 1
                    newCount += 1
                case .delete(let line):
                    hunkLines.append("-" + line)
                    if firstOld == nil { firstOld = item.oldLineNum }
                    if firstNew == nil { firstNew = item.newLineNum ?? max(1, newCount) }
                    oldCount += 1
                case .insert(let line):
                    hunkLines.append("+" + line)
                    if firstOld == nil { firstOld = item.oldLineNum ?? max(1, oldCount) }
                    if firstNew == nil { firstNew = item.newLineNum }
                    newCount += 1
                }
            }

            oldStart = firstOld ?? 1
            newStart = firstNew ?? 1

            hunks.append(DiffHunk(
                oldStart: oldStart,
                oldCount: oldCount,
                newStart: newStart,
                newCount: newCount,
                lines: hunkLines
            ))
        }

        return hunks
    }

    public func computeUnifiedDiff(
        filePath: String,
        oldContent: String,
        newContent: String,
        contextLines: Int = 3
    ) -> UnifiedDiffResult {
        let oldLines = oldContent.components(separatedBy: "\n")
        let newLines = newContent.components(separatedBy: "\n")

        let hunks = computeUnifiedHunks(old: oldLines, new: newLines, contextLines: contextLines)

        var addedCount = 0
        var deletedCount = 0

        for hunk in hunks {
            for line in hunk.lines {
                if line.hasPrefix("+") { addedCount += 1 }
                else if line.hasPrefix("-") { deletedCount += 1 }
            }
        }

        var header = "--- a/\(filePath)\n+++ b/\(filePath)\n"
        if hunks.isEmpty {
            header += "(No changes detected)"
        } else {
            for hunk in hunks {
                header += hunk.header + "\n"
                for line in hunk.lines {
                    header += line + "\n"
                }
            }
        }

        return UnifiedDiffResult(
            filePath: filePath,
            hunks: hunks,
            addedLines: addedCount,
            removedLines: deletedCount,
            unifiedText: header
        )
    }

    public func diff(old: [String], new: [String]) -> [GitDiffHunk] {
        let hunks = computeUnifiedHunks(old: old, new: new, contextLines: 3)
        if hunks.isEmpty {
            return []
        }
        return hunks.map { GitDiffHunk(header: $0.header, lines: $0.lines) }
    }
}

import Observation
import os

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

@Observable
@MainActor
public final class LiveDiffStreamer: Sendable {
    public static let shared = LiveDiffStreamer()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "LiveDiffStreamer")

    public var activeStreams: [String: LiveFileEditEvent] = [:]

    public var recentEdits: [LiveFileEditEvent] = []

    private var sequenceCounter = 0

    public init() {}

    @discardableResult
    public func beginEdit(
        sessionId: String = UUID().uuidString,
        taskId: String = "active_task",
        goalId: String = "active_goal",
        filePath: String,
        operationType: LiveEditOperationType,
        beforeContent: String
    ) -> String {
        let opId = UUID().uuidString
        sequenceCounter += 1

        let event = LiveFileEditEvent(
            sessionId: sessionId,
            taskId: taskId,
            goalId: goalId,
            filePath: filePath,
            operationId: opId,
            operationType: operationType,
            sequenceNumber: sequenceCounter,
            beforeContent: beforeContent,
            currentContent: beforeContent,
            hunks: [],
            addedLineCount: 0,
            deletedLineCount: 0,
            isFinal: false,
            isReconciled: false
        )

        activeStreams[filePath] = event
        logger.info("[beginEdit] Initialized live edit for '\(filePath)' (Op: \(operationType.rawValue), Seq: \(self.sequenceCounter))")

        DiagnosticEventBus.shared.logEvent(
            component: "LiveDiffStreamer",
            severity: "INFO",
            category: "diff_stream",
            message: "In-flight edit started: \(filePath) [\(operationType.rawValue)]"
        )

        return opId
    }

    public func streamMutation(
        filePath: String,
        currentContent: String,
        isFinal: Bool = false
    ) {
        guard var event = activeStreams[filePath] else {
            _ = beginEdit(
                filePath: filePath,
                operationType: .write,
                beforeContent: ""
            )
            streamMutation(filePath: filePath, currentContent: currentContent, isFinal: isFinal)
            return
        }

        sequenceCounter += 1
        event.sequenceNumber = sequenceCounter
        event.currentContent = currentContent
        event.isFinal = isFinal

        let diffResult = MyersDiffAlgorithm.shared.computeUnifiedDiff(
            filePath: filePath,
            oldContent: event.beforeContent,
            newContent: currentContent,
            contextLines: 3
        )

        event.hunks = diffResult.hunks
        event.addedLineCount = diffResult.addedLines
        event.deletedLineCount = diffResult.removedLines

        activeStreams[filePath] = event

        logger.debug("[streamMutation] Streamed '\(filePath)': +\(diffResult.addedLines) / -\(diffResult.removedLines) lines (\(diffResult.hunks.count) hunks)")
    }

    public func completeEdit(
        filePath: String,
        finalContent: String
    ) {
        streamMutation(filePath: filePath, currentContent: finalContent, isFinal: true)

        if var event = activeStreams[filePath] {
            event.isFinal = true
            event.isReconciled = true

            activeStreams[filePath] = event

            if let index = recentEdits.firstIndex(where: { $0.filePath == filePath && $0.operationId == event.operationId }) {
                recentEdits[index] = event
            } else {
                recentEdits.append(event)
            }

            logger.info("[completeEdit] Finalized edit for '\(filePath)': +\(event.addedLineCount) / -\(event.deletedLineCount)")
        }
    }

    public func reconcileWithDisk(
        filePath: String,
        actualDiskContent: String
    ) {
        guard var event = activeStreams[filePath] ?? recentEdits.first(where: { $0.filePath == filePath }) else {
            return
        }

        if event.currentContent != actualDiskContent {
            logger.warning("[reconcileWithDisk] Mismatch detected on '\(filePath)'. Recomputing Myers diff with actual disk state...")
            let correctedDiff = MyersDiffAlgorithm.shared.computeUnifiedDiff(
                filePath: filePath,
                oldContent: event.beforeContent,
                newContent: actualDiskContent,
                contextLines: 3
            )

            event.currentContent = actualDiskContent
            event.hunks = correctedDiff.hunks
            event.addedLineCount = correctedDiff.addedLines
            event.deletedLineCount = correctedDiff.removedLines
        }

        event.isReconciled = true
        activeStreams[filePath] = event

        if let index = recentEdits.firstIndex(where: { $0.filePath == filePath }) {
            recentEdits[index] = event
        } else {
            recentEdits.append(event)
        }

        DiagnosticEventBus.shared.logEvent(
            component: "LiveDiffStreamer",
            severity: "SUCCESS",
            category: "diff_reconciliation",
            message: "Reconciled diff with disk for: \(filePath) (+\(event.addedLineCount)/-\(event.deletedLineCount))"
        )
    }

    public func cancelStream(filePath: String) {
        activeStreams.removeValue(forKey: filePath)
        logger.info("[cancelStream] Cancelled active stream for '\(filePath)'")
    }

    public func clearAll() {
        activeStreams.removeAll()
        recentEdits.removeAll()
        sequenceCounter = 0
    }
}
