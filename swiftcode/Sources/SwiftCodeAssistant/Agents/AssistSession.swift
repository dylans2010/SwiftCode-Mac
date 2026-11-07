import Foundation
import Observation

@Observable
@MainActor
public final class AssistSession: Sendable {
    public let id: UUID
    public let startTime: Date
    public var currentPlan: AssistExecutionPlan?
    public var history: [AssistExecutionPlan] = []

    public init() {
        self.id = UUID()
        self.startTime = Date()
    }

    public func addPlan(_ plan: AssistExecutionPlan) {
        currentPlan = plan
        history.append(plan)
    }

    public func reset() {
        currentPlan = nil
        history.removeAll()
    }
}
