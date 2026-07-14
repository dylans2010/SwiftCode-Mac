import Foundation

public struct DeveloperWorkflow: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var description: String
    public var icon: String
    public var category: String
    public var isFavorite: Bool = false
    public var steps: [WorkflowStep] = []
    public var customCommands: String = "" // CLI Canvas custom commands content
    public var useCLIOnly: Bool = false   // Toggle to bypass guided builder steps

    public init(name: String, description: String, icon: String, category: String, steps: [WorkflowStep] = []) {
        self.name = name
        self.description = description
        self.icon = icon
        self.category = category
        self.steps = steps
    }
}

public struct WorkflowStep: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var name: String
    public var description: String
    public var icon: String
    public var category: String
    public var estimatedDuration: Double // in seconds
    public var inputs: [String: String] = [:]
    public var isOptional: Bool = false
    public var retryCount: Int = 0

    public init(name: String, description: String, icon: String, category: String, estimatedDuration: Double, inputs: [String: String] = [:]) {
        self.name = name
        self.description = description
        self.icon = icon
        self.category = category
        self.estimatedDuration = estimatedDuration
        self.inputs = inputs
    }
}

public struct WorkflowHistoryEntry: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var workflowName: String
    public var timestamp = Date()
    public var duration: Double
    public var success: Bool
    public var logs: String

    public init(workflowName: String, duration: Double, success: Bool, logs: String) {
        self.workflowName = workflowName
        self.duration = duration
        self.success = success
        self.logs = logs
    }
}
