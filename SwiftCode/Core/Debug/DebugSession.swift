import Foundation

public struct DebugSession: Identifiable, Sendable {
    public let id: UUID
    public let pid: Int32
    public let startedAt: Date
    public var state: State
    public let executableURL: URL

    public enum State: Sendable {
        case launching
        case running
        case terminated(Int32)
    }

    public init(pid: Int32, executableURL: URL) {
        self.id = UUID()
        self.pid = pid
        self.startedAt = Date()
        self.state = .launching
        self.executableURL = executableURL
    }
}
