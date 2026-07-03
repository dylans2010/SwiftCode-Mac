import Foundation

public struct BuildTargetInfo: Identifiable, Sendable, Codable {
    public var id: String { name }
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}
