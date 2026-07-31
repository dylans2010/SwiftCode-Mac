import Foundation

public struct DatabaseTemplate: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var category: String
    public var description: String
    public var tags: [String]
    public var tables: [DatabaseTable]
    public var isFavorite: Bool

    public init(id: UUID = UUID(), name: String, category: String, description: String, tags: [String] = [], tables: [DatabaseTable] = [], isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.tags = tags
        self.tables = tables
        self.isFavorite = isFavorite
    }
}
