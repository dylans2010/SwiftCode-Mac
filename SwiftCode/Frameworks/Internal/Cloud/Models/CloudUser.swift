import Foundation

public struct CloudUser: Codable, Sendable, Equatable, Identifiable {
    public var id: String { swiftcodeID }
    public let swiftcodeID: String
    public let email: String
    public let name: String?
    public let createdAt: Date

    public init(swiftcodeID: String, email: String, name: String? = nil, createdAt: Date = Date()) {
        self.swiftcodeID = swiftcodeID
        self.email = email
        self.name = name
        self.createdAt = createdAt
    }
}
