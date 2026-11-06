// Moved here from SwiftCodeMCP/Tools/UseTermFunction.swift by MCP-DEP (2026-11-06,
// decision (b) in staging-wire/mcp-dep/DISPOSITIONS.md). Foundation-only struct;
// SwiftCodeAssistant (which cannot import SwiftCodeMCP) needs it for
// AssistManager.pendingTerminalRequest / requestTerminalApproval. SwiftCodeMCP
// keeps using it through `import SwiftCodeAssistant`. Body verbatim.

import Foundation

public struct TerminalApprovalRequest: Identifiable, Sendable {
    public let id: UUID
    public let command: String
    public let workingDirectory: String
    public let explanation: String
    public let estimatedImpact: String
    public let modifiesRepo: Bool

    public init(id: UUID = UUID(), command: String, workingDirectory: String, explanation: String, estimatedImpact: String, modifiesRepo: Bool) {
        self.id = id
        self.command = command
        self.workingDirectory = workingDirectory
        self.explanation = explanation
        self.estimatedImpact = estimatedImpact
        self.modifiesRepo = modifiesRepo
    }
}
