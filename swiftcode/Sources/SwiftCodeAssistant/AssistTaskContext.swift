// Ported from SwiftCode-Legacy SwiftCode/Backend/Assist/AssistTaskContext.swift (Dylan's own code;
// direct port authorised under MIT). Legacy commit d51a8f0d; destination
// SwiftCode-Mac main f5de49dd. Landed on main by fix agent W-V2 (baseline bc28f653).
// Dependency of staged AssistModels.swift (AssistMessage.envelope:
// AssistTaskEnvelope). Ported verbatim. Depends on destination SkillDescriptor
// (SwiftCodeAssistant/SkillDescriptor.swift) and staged AgentFileContext +
// ReverseInvocation (ReverseModels.swift).
// See staging-ma/assist-core/_notes/agent-feedback-decisions.md.
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
