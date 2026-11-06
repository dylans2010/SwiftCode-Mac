// Adapted from SwiftCode-Legacy SwiftCode/Core/Build/BuildScheme.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct BuildScheme: Identifiable, Sendable, Codable, Equatable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}
