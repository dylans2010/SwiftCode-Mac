// Adapted from SwiftCode-Legacy SwiftCode/Core/Debug/DebugModels.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct StackFrame: Identifiable, Sendable {
    public let id: Int
    public let function: String
    public let location: String
    public var isActive: Bool

    public init(id: Int, function: String, location: String, isActive: Bool = false) {
        self.id = id
        self.function = function
        self.location = location
        self.isActive = isActive
    }
}

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
