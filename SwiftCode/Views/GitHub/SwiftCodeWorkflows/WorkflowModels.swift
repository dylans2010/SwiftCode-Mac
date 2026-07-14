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

    // Asynchronous terminal background execution properties
    public var command: String = ""
    public var workingDirectory: String = ""
    public var environmentVariables: String = ""
    public var timeout: Double = 300.0
    public var outputVariableName: String = ""

    public init(
        name: String,
        description: String,
        icon: String,
        category: String,
        estimatedDuration: Double,
        inputs: [String: String] = [:],
        command: String = "",
        workingDirectory: String = "",
        environmentVariables: String = "",
        timeout: Double = 300.0,
        outputVariableName: String = ""
    ) {
        self.name = name
        self.description = description
        self.icon = icon
        self.category = category
        self.estimatedDuration = estimatedDuration
        self.inputs = inputs
        self.command = command
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.timeout = timeout
        self.outputVariableName = outputVariableName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.icon = try container.decode(String.self, forKey: .icon)
        self.category = try container.decode(String.self, forKey: .category)
        self.estimatedDuration = try container.decode(Double.self, forKey: .estimatedDuration)
        self.inputs = try container.decodeIfPresent([String: String].self, forKey: .inputs) ?? [:]
        self.isOptional = try container.decodeIfPresent(Bool.self, forKey: .isOptional) ?? false
        self.retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        self.command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        self.workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? ""
        self.environmentVariables = try container.decodeIfPresent(String.self, forKey: .environmentVariables) ?? ""
        self.timeout = try container.decodeIfPresent(Double.self, forKey: .timeout) ?? 300.0
        self.outputVariableName = try container.decodeIfPresent(String.self, forKey: .outputVariableName) ?? ""
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
