import Foundation

public struct DatabaseTable: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var columns: [DatabaseColumn]
    public var relationships: [DatabaseRelationship]
    public var indexes: [DatabaseIndex]
    public var triggers: [DatabaseTrigger]
    public var isView: Bool
    public var isMaterializedView: Bool
    public var comment: String?
    public var recordCount: Int

    public init(name: String, columns: [DatabaseColumn] = [], relationships: [DatabaseRelationship] = [], indexes: [DatabaseIndex] = [], triggers: [DatabaseTrigger] = [], isView: Bool = false, isMaterializedView: Bool = false, comment: String? = nil, recordCount: Int = 0) {
        self.name = name
        self.columns = columns
        self.relationships = relationships
        self.indexes = indexes
        self.triggers = triggers
        self.isView = isView
        self.isMaterializedView = isMaterializedView
        self.comment = comment
        self.recordCount = recordCount
    }
}
