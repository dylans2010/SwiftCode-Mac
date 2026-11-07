import Foundation
import os

@MainActor
public final class WorkerFileTracker: Sendable {
    public static let shared = WorkerFileTracker()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerFileTracker")
    private var ownerships: [String: WorkerFileOwnership] = [:]

    private init() {}

    public func recordMutation(
        workerID: UUID,
        path: String,
        type: FileChangeType,
        previousContent: String? = nil,
        newContent: String? = nil,
        previousPath: String? = nil
    ) {
        var linesAdded = 0
        var linesRemoved = 0

        if let prev = previousContent, let next = newContent {
            let prevLines = prev.components(separatedBy: "\n").count
            let nextLines = next.components(separatedBy: "\n").count
            if nextLines >= prevLines {
                linesAdded = nextLines - prevLines
            } else {
                linesRemoved = prevLines - nextLines
            }
        } else if let next = newContent {
            linesAdded = next.components(separatedBy: "\n").count
        } else if let prev = previousContent {
            linesRemoved = prev.components(separatedBy: "\n").count
        }

        let change = WorkerFileChange(
            path: path,
            changeType: type,
            previousPath: previousPath,
            timestamp: Date(),
            linesAdded: linesAdded,
            linesRemoved: linesRemoved
        )

        WorkerRuntimeState.shared.recordFileChange(id: workerID, change: change)
        logger.info("[Worker \(workerID)] Recorded file \(type.rawValue): \(path) (+\(linesAdded)/-\(linesRemoved))")
    }

    public func registerOwnership(
        workerID: UUID,
        workerName: String,
        filePath: String,
        ownershipType: FileOwnershipType
    ) {
        let ownership = WorkerFileOwnership(
            workerID: workerID,
            workerName: workerName,
            filePath: filePath,
            ownershipType: ownershipType
        )
        ownerships[filePath] = ownership
        logger.info("[Worker \(workerName)] Registered \(ownershipType.rawValue) ownership of \(filePath)")
    }

    public func checkConflict(filePath: String, requestingWorkerID: UUID) -> WorkerFileOwnership? {
        guard let existing = ownerships[filePath] else { return nil }
        guard existing.workerID != requestingWorkerID else { return nil }
        guard existing.ownershipType == .exclusive else { return nil }
        return existing
    }

    public func transferOwnership(
        filePath: String,
        fromWorkerID: UUID,
        toWorkerID: UUID,
        toWorkerName: String
    ) -> Bool {
        guard let existing = ownerships[filePath], existing.workerID == fromWorkerID else { return false }
        ownerships[filePath] = WorkerFileOwnership(
            workerID: toWorkerID,
            workerName: toWorkerName,
            filePath: filePath,
            ownershipType: existing.ownershipType
        )
        logger.info("[Worker \(toWorkerName)] Transferred ownership of \(filePath) from \(fromWorkerID)")
        return true
    }

    public func releaseOwnership(filePath: String, workerID: UUID) {
        guard let existing = ownerships[filePath], existing.workerID == workerID else { return }
        ownerships.removeValue(forKey: filePath)
    }

    public func releaseAllOwnerships(workerID: UUID) {
        ownerships = ownerships.filter { $0.value.workerID != workerID }
    }

    public func getOwnership(filePath: String) -> WorkerFileOwnership? {
        ownerships[filePath]
    }

    public func getFilesOwnedBy(workerID: UUID) -> [String] {
        ownerships.filter { $0.value.workerID == workerID }.map { $0.key }
    }

    public func getAllOwnerships() -> [WorkerFileOwnership] {
        Array(ownerships.values)
    }

    public func clear() {
        ownerships.removeAll()
    }
}
