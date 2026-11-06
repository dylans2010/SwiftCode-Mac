import Foundation

public struct GitBranch: Identifiable, Sendable, Codable {
    public var id: String { name }
    public let name: String
    public let isCurrent: Bool
    public let isRemote: Bool
    public let trackingRemote: String?

    public init(name: String, isCurrent: Bool, isRemote: Bool, trackingRemote: String? = nil) {
        self.name = name
        self.isCurrent = isCurrent
        self.isRemote = isRemote
        self.trackingRemote = trackingRemote
    }
}
