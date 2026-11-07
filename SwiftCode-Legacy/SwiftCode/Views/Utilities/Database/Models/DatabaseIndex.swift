import Foundation

public struct DatabaseIndex: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var columns: [String]
    public var isUnique: Bool
    public var type: String
    public var expression: String?

    public init(name: String, columns: [String], isUnique: Bool = false, type: String = "B-TREE", expression: String? = nil) {
        self.name = name
        self.columns = columns
        self.isUnique = isUnique
        self.type = type
        self.expression = expression
    }
}
