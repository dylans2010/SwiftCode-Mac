import Foundation

public enum AgentChecklistTaskStatus: String, Codable, Sendable {
    case queued
    case inProgress = "in_progress"
    case completed
    case failed
}
