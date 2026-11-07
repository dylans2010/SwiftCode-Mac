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
