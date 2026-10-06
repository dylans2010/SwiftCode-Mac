//
//  AssistTaskContext.swift
//  SwiftCode
//
//  Structured task envelope encapsulating user message, explicit skills, MCP selections, and file context.
//

import Foundation

/// Structured execution state submitted from the Assist composer to the execution runtime.
public struct AssistTaskEnvelope: Sendable {
    public let id: UUID
    public let userMessage: String
    public let explicitSkills: [SkillDescriptor]
    public let explicitMCPServers: [String]
    public let explicitFiles: [AgentFileContext]
    public let submittedAt: Date

    public init(
        id: UUID = UUID(),
        userMessage: String,
        explicitSkills: [SkillDescriptor] = [],
        explicitMCPServers: [String] = [],
        explicitFiles: [AgentFileContext] = [],
        submittedAt: Date = Date()
    ) {
        self.id = id
        self.userMessage = userMessage
        self.explicitSkills = explicitSkills
        self.explicitMCPServers = explicitMCPServers
        self.explicitFiles = explicitFiles
        self.submittedAt = submittedAt
    }
}
