import Foundation

/// Optimizes execution strategies and outputs
public final class AssistOptimizationEngine {
    private let context: AssistContext

    public struct OptimizationResult {
        let wasOptimized: Bool
        let improvements: [String]
        let optimizedPlan: AssistExecutionPlan?
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Optimizes a plan before execution
    public func optimizePlan(_ plan: AssistExecutionPlan) async -> OptimizationResult {
        await context.logger.info("Optimizing execution plan", toolId: "OptimizationEngine")

        var improvements: [String] = []
        var optimizedSteps = plan.steps

        // Optimization 1: Remove duplicate steps
        var seenOperations = Set<String>()
        optimizedSteps = optimizedSteps.filter { step in
            let key = "\(step.toolId):\(step.input)"
            if seenOperations.contains(key) {
                improvements.append("Removed duplicate step: \(step.description)")
                return false
            }
            seenOperations.insert(key)
            return true
        }

        // Optimization 2: Reorder steps for efficiency (reads before writes)
        let readSteps = optimizedSteps.filter { ["file_read", "readFile"].contains($0.toolId) }
        let writeSteps = optimizedSteps.filter { ["file_write", "createFile"].contains($0.toolId) }
        let otherSteps = optimizedSteps.filter {
            !["file_read", "readFile", "file_write", "createFile"].contains($0.toolId)
        }

        if readSteps.count + writeSteps.count + otherSteps.count < optimizedSteps.count {
            // Some reordering possible
            optimizedSteps = readSteps + otherSteps + writeSteps
            if !readSteps.isEmpty && !writeSteps.isEmpty {
                improvements.append("Reordered steps for efficiency (reads before writes)")
            }
        }

        // Optimization 3: Batch similar operations
        // (Could implement more sophisticated batching here)

        let wasOptimized = !improvements.isEmpty

        if wasOptimized {
            var optimizedPlan = plan
            optimizedPlan.steps = optimizedSteps
            await context.logger.info("Plan optimized: \(improvements.joined(separator: ", "))", toolId: "OptimizationEngine")
            return OptimizationResult(wasOptimized: true, improvements: improvements, optimizedPlan: optimizedPlan)
        }

        return OptimizationResult(wasOptimized: false, improvements: [], optimizedPlan: nil)
    }
}
