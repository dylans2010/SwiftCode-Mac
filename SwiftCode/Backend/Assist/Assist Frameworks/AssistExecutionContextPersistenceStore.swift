import Foundation

/// Stores and retrieves persistent context across execution sessions
public final class AssistExecutionContextPersistenceStore {
    private let context: AssistContext
    private let storageKey = "com.swiftcode.assist.persistentContext"

    public struct PersistentContext: Codable {
        let sessionId: String
        let startTime: Date
        let originalGoal: String
        let completedTasks: [String]
        let expandedGoals: [String]
        let currentIteration: Int
        let totalStepsExecuted: Int
    }

    public init(context: AssistContext) {
        self.context = context
    }

    /// Saves current context state
    public func saveContext(
        goal: String,
        completedTasks: [String],
        expandedGoals: [String],
        iteration: Int,
        stepsExecuted: Int
    ) async {
        let persistentContext = PersistentContext(
            sessionId: context.sessionId.uuidString,
            startTime: Date(),
            originalGoal: goal,
            completedTasks: completedTasks,
            expandedGoals: expandedGoals,
            currentIteration: iteration,
            totalStepsExecuted: stepsExecuted
        )

        if let data = try? JSONEncoder().encode(persistentContext) {
            UserDefaults.standard.set(data, forKey: storageKey)
            await context.logger.info("Context persisted (iteration \(iteration))", toolId: "ContextPersistence")
        }
    }

    /// Loads saved context
    public func loadContext() -> PersistentContext? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let persistentContext = try? JSONDecoder().decode(PersistentContext.self, from: data) else {
            return nil
        }
        return persistentContext
    }

    /// Clears persisted context
    public func clearContext() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
