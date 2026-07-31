import Foundation

public struct DatabaseColumn: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var type: String // e.g. TEXT, INTEGER, VARCHAR(255), uuid, etc.
    public var isPrimaryKey: Bool
    public var isForeignKey: Bool
    public var isNullable: Bool
    public var isUnique: Bool
    public var isAutoIncrement: Bool
    public var isGenerated: Bool
    public var generationExpression: String?
    public var defaultValue: String?
    public var checkConstraint: String?
    public var comment: String?

    public init(name: String, type: String, isPrimaryKey: Bool = false, isForeignKey: Bool = false, isNullable: Bool = true, isUnique: Bool = false, isAutoIncrement: Bool = false, isGenerated: Bool = false, generationExpression: String? = nil, defaultValue: String? = nil, checkConstraint: String? = nil, comment: String? = nil) {
        self.name = name
        self.type = type
        self.isPrimaryKey = isPrimaryKey
        self.isForeignKey = isForeignKey
        self.isNullable = isNullable
        self.isUnique = isUnique
        self.isAutoIncrement = isAutoIncrement
        self.isGenerated = isGenerated
        self.generationExpression = generationExpression
        self.defaultValue = defaultValue
        self.checkConstraint = checkConstraint
        self.comment = comment
    }
}
