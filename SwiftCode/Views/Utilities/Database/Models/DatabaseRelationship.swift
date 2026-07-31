import Foundation

public enum RelationshipType: String, Codable, CaseIterable {
    case oneToOne = "One-to-One"
    case oneToMany = "One-to-Many"
    case manyToMany = "Many-to-Many"
}

public enum ReferentialAction: String, Codable, CaseIterable {
    case cascade = "CASCADE"
    case restrict = "RESTRICT"
    case setNull = "SET NULL"
    case setDefault = "SET DEFAULT"
    case noAction = "NO ACTION"
}

public struct DatabaseRelationship: Identifiable, Codable, Hashable {
    public var id: UUID
    public var type: RelationshipType
    public var sourceTable: String
    public var sourceColumn: String
    public var targetTable: String
    public var targetColumn: String
    public var junctionTable: String? // for Many-to-Many relationships
    public var onDelete: ReferentialAction
    public var onUpdate: ReferentialAction

    public init(id: UUID = UUID(), type: RelationshipType, sourceTable: String, sourceColumn: String, targetTable: String, targetColumn: String, junctionTable: String? = nil, onDelete: ReferentialAction = .cascade, onUpdate: ReferentialAction = .cascade) {
        self.id = id
        self.type = type
        self.sourceTable = sourceTable
        self.sourceColumn = sourceColumn
        self.targetTable = targetTable
        self.targetColumn = targetColumn
        self.junctionTable = junctionTable
        self.onDelete = onDelete
        self.onUpdate = onUpdate
    }
}
