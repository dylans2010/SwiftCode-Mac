import Foundation

public struct AgentChecklistState: Codable, Sendable {
    public var tasks: [AgentChecklistTask]

    public init(tasks: [AgentChecklistTask]) {
        self.tasks = tasks
    }
}
