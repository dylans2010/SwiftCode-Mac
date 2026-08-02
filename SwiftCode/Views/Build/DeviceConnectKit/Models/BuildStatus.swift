import Foundation

public enum BuildStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case idle = "Idle"
    case building = "Building"
    case succeeded = "Succeeded"
    case failed = "Failed"
    case cancelled = "Cancelled"

    public var description: String {
        return self.rawValue
    }
}
