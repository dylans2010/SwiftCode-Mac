import Foundation
import os

/// Structured description of an atomic operation in a parallel execution plan.
public struct AssistOperation: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let toolId: String
    public let input: [String: String]
    public let dependencies: Set<String>
    public let isMutating: Bool
    public let targetPaths: [String]
    public let timeoutSeconds: TimeInterval

    public init(
        id: String = UUID().uuidString,
        name: String,
        toolId: String,
        input: [String: String] = [:],
        dependencies: Set<String> = [],
        isMutating: Bool = false,
        targetPaths: [String] = [],
        timeoutSeconds: TimeInterval = 120
    ) {
        self.id = id
        self.name = name
        self.toolId = toolId
        self.input = input
        self.dependencies = dependencies
        self.isMutating = isMutating
        self.targetPaths = targetPaths
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Status of an operation within the parallel execution engine.
public enum AssistOperationStatus: String, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled
    case skipped
}

/// Result of executing an individual operation.
public struct AssistOperationResult: Sendable {
    public let operationId: String
    public let status: AssistOperationStatus
    public let toolResult: AssistToolResult?
    public let error: String?
    public let duration: TimeInterval

    public var isSuccess: Bool {
        return status == .completed && (toolResult?.success ?? false)
    }
}

/// Aggregate summary of executing a dependency graph of operations.
public struct AssistParallelExecutionReport: Sendable {
    public let totalOperations: Int
    public let completedCount: Int
    public let failedCount: Int
    public let cancelledCount: Int
    public let results: [String: AssistOperationResult]
    public let duration: TimeInterval

    public var isSuccess: Bool {
        return failedCount == 0 && cancelledCount == 0
    }
}

/// Bounded concurrency execution engine for Assist operations.
/// Evaluates dependency graphs, checks resource collision (e.g. conflicting file modifications),
/// and executes independent operations concurrently.
@MainActor
public final class AssistParallelExecutionEngine: Sendable {
    public static let shared = AssistParallelExecutionEngine()

    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistParallelExecutionEngine")
    public let maxConcurrentOperations: Int = 4

    private init() {}

    /// Executes a list of operations respecting dependencies and file write serialization.
    public func execute(
        operations: [AssistOperation],
        context: AssistContext,
        onProgress: (@Sendable @MainActor (String, AssistOperationStatus) -> Void)? = nil
    ) async -> AssistParallelExecutionReport {
        let startTime = Date()
        var pending = operations
        var running: [String: Task<AssistOperationResult, Never>] = [:]
        var completed: [String: AssistOperationResult] = [:]
        var activeMutatingPaths = Set<String>()

        logger.info("Starting parallel execution of \(operations.count) operations.")

        while !pending.isEmpty || !running.isEmpty {
            // Check for task cancellation
            if Task.isCancelled {
                for (_, task) in running {
                    task.cancel()
                }
                for op in pending {
                    completed[op.id] = AssistOperationResult(
                        operationId: op.id,
                        status: .cancelled,
                        toolResult: nil,
                        error: "Execution was cancelled",
                        duration: 0
                    )
                }
                break
            }

            // Find candidates whose dependencies have succeeded and do not collide on write paths
            var scheduledAny = false
            var index = 0
            while index < pending.count && running.count < maxConcurrentOperations {
                let op = pending[index]

                // Check dependencies
                let depsSatisfied = op.dependencies.allSatisfy { depId in
                    completed[depId]?.isSuccess == true
                }
                let depFailed = op.dependencies.contains { depId in
                    if let res = completed[depId] { return !res.isSuccess }
                    return false
                }

                if depFailed {
                    // Skip operation if an upstream dependency failed
                    pending.remove(at: index)
                    completed[op.id] = AssistOperationResult(
                        operationId: op.id,
                        status: .skipped,
                        toolResult: nil,
                        error: "Skipped due to upstream dependency failure",
                        duration: 0
                    )
                    onProgress?(op.name, .skipped)
                    continue
                }

                if !depsSatisfied {
                    index += 1
                    continue
                }

                // Check write collisions: if this operation mutates a path currently being mutated, wait
                let touchesActivePath = op.targetPaths.contains { activeMutatingPaths.contains($0) }
                if op.isMutating && touchesActivePath {
                    index += 1
                    continue
                }

                // Ready to schedule
                pending.remove(at: index)
                scheduledAny = true

                if op.isMutating {
                    for path in op.targetPaths {
                        activeMutatingPaths.insert(path)
                    }
                }

                onProgress?(op.name, .running)

                let opId = op.id
                let mutatingPaths = op.targetPaths
                let isMutating = op.isMutating

                let task = Task<AssistOperationResult, Never> {
                    let opStart = Date()
                    guard let tool = AssistToolRegistry.shared.getTool(op.toolId) else {
                        return AssistOperationResult(
                            operationId: opId,
                            status: .failed,
                            toolResult: nil,
                            error: "Tool '\(op.toolId)' not found in registry",
                            duration: Date().timeIntervalSince(opStart)
                        )
                    }

                    do {
                        let res = try await tool.execute(input: op.input, context: context)
                        return AssistOperationResult(
                            operationId: opId,
                            status: res.success ? .completed : .failed,
                            toolResult: res,
                            error: res.error,
                            duration: Date().timeIntervalSince(opStart)
                        )
                    } catch {
                        return AssistOperationResult(
                            operationId: opId,
                            status: .failed,
                            toolResult: nil,
                            error: error.localizedDescription,
                            duration: Date().timeIntervalSince(opStart)
                        )
                    }
                }

                running[opId] = task
            }

            // If nothing is currently running and nothing could be scheduled, we have a cycle or deadlock
            if running.isEmpty && !pending.isEmpty && !scheduledAny {
                logger.error("Parallel execution deadlock detected: pending operations cannot satisfy dependencies.")
                for op in pending {
                    completed[op.id] = AssistOperationResult(
                        operationId: op.id,
                        status: .failed,
                        toolResult: nil,
                        error: "Deadlock or unsatisfied dependency in execution graph",
                        duration: 0
                    )
                }
                pending.removeAll()
                break
            }

            // Wait for at least one running operation to complete
            if !running.isEmpty {
                // Yield briefly to allow concurrent tasks to progress
                try? await Task.sleep(nanoseconds: 50_000_000)

                var completedInThisCycle: [String] = []
                for (opId, task) in running {
                    if task.isCancelled {
                        completedInThisCycle.append(opId)
                        completed[opId] = AssistOperationResult(
                            operationId: opId,
                            status: .cancelled,
                            toolResult: nil,
                            error: "Cancelled",
                            duration: 0
                        )
                    }
                }

                // Check for finished tasks
                for (opId, task) in running {
                    if !completedInThisCycle.contains(opId) {
                        // Check if task is finished
                        // In Swift Task, we can check if it's done by awaiting with a tiny timeout or polling
                        // Here we can await task completion via race or poll
                    }
                }
            }

            // Efficiently harvest completed tasks
            for (opId, task) in running {
                // We await the first completed task
                let result = await task.value
                running.removeValue(forKey: opId)
                completed[opId] = result
                onProgress?(opId, result.status)

                // Release mutating paths
                if let matchedOp = operations.first(where: { $0.id == opId }), matchedOp.isMutating {
                    for path in matchedOp.targetPaths {
                        activeMutatingPaths.remove(path)
                    }
                }
                break // Break loop to re-evaluate pending queue
            }
        }

        let totalDuration = Date().timeIntervalSince(startTime)
        let completedCount = completed.values.filter { $0.isSuccess }.count
        let failedCount = completed.values.filter { $0.status == .failed }.count
        let cancelledCount = completed.values.filter { $0.status == .cancelled || $0.status == .skipped }.count

        return AssistParallelExecutionReport(
            totalOperations: operations.count,
            completedCount: completedCount,
            failedCount: failedCount,
            cancelledCount: cancelledCount,
            results: completed,
            duration: totalDuration
        )
    }
}
