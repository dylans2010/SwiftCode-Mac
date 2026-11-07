import Foundation

public enum SDKConsoleStream: String, Sendable, Codable, CaseIterable, Hashable {
    case stdout
    case stderr
    case system
}

public struct SDKConsoleEntry: Identifiable, Sendable, Hashable {
    public static let maxTextLength: Int = 4_096

    public let id: UUID
    public let timestamp: Date
    public let stream: SDKConsoleStream
    public let text: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        stream: SDKConsoleStream,
        text: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.stream = stream
        self.text = text
    }

    public static func system(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .system, text: text)
    }

    public static func stdout(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .stdout, text: text)
    }

    public static func stderr(_ text: String, at date: Date = Date()) -> SDKConsoleEntry {
        SDKConsoleEntry(timestamp: date, stream: .stderr, text: text)
    }
}
