import Foundation

public struct BuildScheme: Identifiable, Sendable, Codable, Equatable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
