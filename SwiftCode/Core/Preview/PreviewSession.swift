import Foundation

/// Represents the status of an active preview compilation or render loop.
public enum PreviewSessionStatus: String, Codable, Sendable, CaseIterable {
    case idle = "Idle"
    case compiling = "Compiling"
    case running = "Running"
    case paused = "Paused"
    case failed = "Failed"
}

/// Models a single active live preview compilation and rendering session.
public struct PreviewSession: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let targetFileURL: URL
    public var status: PreviewSessionStatus
    public var logs: [String]
    public var error: PreviewError?
    public var frameCount: Int
    public var compileDuration: Double?
    public var lastRefreshed: Date

    public init(
        id: UUID = UUID(),
        targetFileURL: URL,
        status: PreviewSessionStatus = .idle,
        logs: [String] = [],
        error: PreviewError? = nil,
        frameCount: Int = 0,
        compileDuration: Double? = nil,
        lastRefreshed: Date = Date()
    ) {
        self.id = id
        self.targetFileURL = targetFileURL
        self.status = status
        self.logs = logs
        self.error = error
        self.frameCount = frameCount
        self.compileDuration = compileDuration
        self.lastRefreshed = lastRefreshed
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: PreviewSession, rhs: PreviewSession) -> Bool {
        lhs.id == rhs.id
    }
}
