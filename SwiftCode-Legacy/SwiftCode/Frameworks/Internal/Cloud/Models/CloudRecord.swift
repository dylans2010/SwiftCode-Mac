import Foundation

public struct CloudRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let swiftcodeID: String
    public let recordType: String
    public let recordKey: String
    public let payload: [String: String]
    public let version: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        swiftcodeID: String,
        recordType: String,
        recordKey: String,
        payload: [String: String],
        version: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.swiftcodeID = swiftcodeID
        self.recordType = recordType
        self.recordKey = recordKey
        self.payload = payload
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case swiftcodeID = "swiftcode_id"
        case recordType = "record_type"
        case recordKey = "record_key"
        case payload
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
