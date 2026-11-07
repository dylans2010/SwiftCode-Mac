import Foundation

@MainActor
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

    public func optimizePlan(_ plan: AssistExecutionPlan) async -> OptimizationResult {
        await context.logger.info("Optimizing execution plan", toolId: "OptimizationEngine")

        var improvements: [String] = []
        var optimizedSteps = plan.steps

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

        let readSteps = optimizedSteps.filter { ["file_read", "readFile"].contains($0.toolId) }
        let writeSteps = optimizedSteps.filter { ["file_write", "createFile"].contains($0.toolId) }
        let otherSteps = optimizedSteps.filter {
            !["file_read", "readFile", "file_write", "createFile"].contains($0.toolId)
        }

        if readSteps.count + writeSteps.count + otherSteps.count < optimizedSteps.count {
            optimizedSteps = readSteps + otherSteps + writeSteps
            if !readSteps.isEmpty && !writeSteps.isEmpty {
                improvements.append("Reordered steps for efficiency (reads before writes)")
            }
        }

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
