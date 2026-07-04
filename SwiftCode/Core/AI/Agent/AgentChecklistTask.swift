import Foundation

public struct AgentChecklistTask: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public var status: AgentChecklistTaskStatus
    public let detail: String?

    public init(id: String, title: String, status: AgentChecklistTaskStatus, detail: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}
