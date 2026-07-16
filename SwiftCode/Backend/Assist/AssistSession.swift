import Foundation

public final class AssistSession: ObservableObject {
    public let id: UUID
    public let startTime: Date
    @Published public var currentPlan: AssistExecutionPlan?
    @Published public var history: [AssistExecutionPlan] = []

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
