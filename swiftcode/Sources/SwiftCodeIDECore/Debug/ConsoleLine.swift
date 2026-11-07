import Foundation

public struct ConsoleLine: Identifiable, Sendable, Codable {
    public let id: UUID
    public let stream: Stream
    public let text: String
    public let timestamp: Date

    public enum Stream: String, Sendable, Codable {
        case stdout
        case stderr
        case system
    }

    public init(stream: Stream, text: String) {
        self.id = UUID()
        self.stream = stream
        self.text = text
        self.timestamp = Date()
    }
}
