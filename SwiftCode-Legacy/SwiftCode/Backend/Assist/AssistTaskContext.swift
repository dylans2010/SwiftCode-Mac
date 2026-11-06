//
//  AssistTaskContext.swift
//  SwiftCode
//
//  Structured task envelope encapsulating user message, explicit skills, MCP selections,
//  slash command directives, and file context.
//

import Foundation

/// Structured execution state submitted from the Assist composer to the execution runtime.
public struct AssistTaskEnvelope: Codable, Sendable, Equatable {
    public let id: UUID
    public let userMessage: String
    public let explicitSkills: [SkillDescriptor]
    public let explicitMCPServers: [String]
    public let explicitFiles: [AgentFileContext]
    public let submittedAt: Date
    public var slashCommand: String?
    public var commandArgument: String?
    public var executedResources: [String]?
    public var taskRule: String?
    public var metadata: [String: String]?
    /// Structured `@Reverse` invocation parsed from the composer text
    /// (see ReverseCommandParser). Nil for ordinary messages.
    public var reverseInvocation: ReverseInvocation?

    public init(
        id: UUID = UUID(),
        userMessage: String,
        explicitSkills: [SkillDescriptor] = [],
        explicitMCPServers: [String] = [],
        explicitFiles: [AgentFileContext] = [],
        submittedAt: Date = Date(),
        slashCommand: String? = nil,
        commandArgument: String? = nil,
        executedResources: [String]? = nil,
        taskRule: String? = nil,
        metadata: [String: String]? = nil,
        reverseInvocation: ReverseInvocation? = nil
    ) {
        self.id = id
        self.userMessage = userMessage
        self.explicitSkills = explicitSkills
        self.explicitMCPServers = explicitMCPServers
        self.explicitFiles = explicitFiles
        self.submittedAt = submittedAt
        self.slashCommand = slashCommand
        self.commandArgument = commandArgument
        self.executedResources = executedResources
        self.taskRule = taskRule
        self.metadata = metadata
        self.reverseInvocation = reverseInvocation
    }

    public var hasExecutedCommandOrResource: Bool {
        slashCommand != nil ||
        (executedResources != nil && !executedResources!.isEmpty) ||
        !explicitSkills.isEmpty ||
        !explicitMCPServers.isEmpty ||
        taskRule != nil ||
        reverseInvocation != nil
    }
}
