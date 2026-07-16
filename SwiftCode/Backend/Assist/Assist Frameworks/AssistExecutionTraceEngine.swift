import Foundation

/// Traces execution path for debugging and analysis
public final class AssistExecutionTraceEngine {
    private let context: AssistContext
    private var trace: [TraceEntry] = []

    public struct TraceEntry {
        let timestamp: Date
        let iteration: Int
        let eventType: EventType
        let description: String
        let metadata: [String: String]
    }

    public enum EventType: String {
        case iterationStart
        case planGenerated
        case executionStarted
        case stepCompleted
        case stepFailed
        case validationPerformed
        case decisionMade
        case goalExpanded
        case iterationEnd
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Records a trace event
    public func recordEvent(
        iteration: Int,
        type: EventType,
        description: String,
        metadata: [String: String] = [:]
    ) {
        let entry = TraceEntry(
            timestamp: Date(),
            iteration: iteration,
            eventType: type,
            description: description,
            metadata: metadata
        )
        trace.append(entry)

        // Also log to assist logger
        Task {
            await context.logger.info("[\(type.rawValue)] \(description)", toolId: "ExecutionTrace")
        }
    }

    /// Gets the full trace log
    public func getTrace() -> [TraceEntry] {
        return trace
    }

    /// Gets trace for a specific iteration
    public func getTrace(forIteration iteration: Int) -> [TraceEntry] {
        return trace.filter { $0.iteration == iteration }
    }

    /// Exports trace to formatted string
    public func exportTrace() -> String {
        var output = "=== ASSIST EXECUTION TRACE ===\n\n"

        for entry in trace {
            let timestamp = ISO8601DateFormatter().string(from: entry.timestamp)
            output += "[\(timestamp)] Iteration \(entry.iteration) - \(entry.eventType.rawValue)\n"
            output += "  \(entry.description)\n"
            if !entry.metadata.isEmpty {
                output += "  Metadata: \(entry.metadata)\n"
            }
            output += "\n"
        }

        return output
    }

    /// Clears the trace
    public func clearTrace() {
        trace.removeAll()
    }
}
