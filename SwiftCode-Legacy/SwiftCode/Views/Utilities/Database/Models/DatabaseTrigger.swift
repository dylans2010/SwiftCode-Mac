import Foundation

public struct DatabaseTrigger: Identifiable, Codable, Hashable {
    public var id: String { name }
    public var name: String
    public var event: String // BEFORE INSERT, AFTER UPDATE, etc.
    public var tableName: String
    public var actionStatement: String

    public init(name: String, event: String, tableName: String, actionStatement: String) {
        self.name = name
        self.event = event
        self.tableName = tableName
        self.actionStatement = actionStatement
    }
}
