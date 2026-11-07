import Foundation

public struct DebugVariable: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let value: String
    public let type: String

    public init(name: String, value: String, type: String) {
        self.id = UUID()
        self.name = name
        self.value = value
        self.type = type
    }
}
