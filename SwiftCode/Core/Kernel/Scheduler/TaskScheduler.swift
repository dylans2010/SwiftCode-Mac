import Foundation

/// Manages task execution and scheduling within the Kernel.
public actor TaskScheduler {
    public static let shared = TaskScheduler()

    public enum Priority: Int, Comparable, Sendable {
        case low = 0
        case medium = 1
        case high = 2
        case critical = 3

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private var taskQueue: [ScheduledTask] = []
    private var isProcessing = false

    private init() {}

    /// Schedules a task for execution.
    public func schedule(priority: Priority = .medium, operation: @escaping @Sendable () async -> Void) {
        let task = ScheduledTask(priority: priority, operation: operation)
        taskQueue.append(task)

        // Sort by priority (highest first)
        taskQueue.sort { $0.priority > $1.priority }

        if !isProcessing {
            Task {
                await processQueue()
            }
        }
    }

    private func processQueue() async {
        isProcessing = true
        defer { isProcessing = false }

        while !taskQueue.isEmpty {
            let task = taskQueue.removeFirst()
            await task.operation()
        }
    }
}

private struct ScheduledTask: Sendable {
    let priority: TaskScheduler.Priority
    let operation: @Sendable () async -> Void
}
