import Foundation

@MainActor
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

        Task {
            await context.logger.info("[\(type.rawValue)] \(description)", toolId: "ExecutionTrace")
        }
    }

    public func getTrace() -> [TraceEntry] {
        return trace
    }

    public func getTrace(forIteration iteration: Int) -> [TraceEntry] {
        return trace.filter { $0.iteration == iteration }
    }

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

    public func clearTrace() {
        trace.removeAll()
    }
}
