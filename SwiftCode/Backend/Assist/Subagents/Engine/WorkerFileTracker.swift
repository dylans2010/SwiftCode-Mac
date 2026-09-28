import Foundation
import os

/// Tracks real filesystem operations and changes during an Assist Worker's execution.
/// Ensures all file modifications are captured from live disk events (INV-11).
@MainActor
public final class WorkerFileTracker: Sendable {
    public static let shared = WorkerFileTracker()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkerFileTracker")

    private init() {}

    /// Records an atomic file mutation executed by a Worker
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
}
