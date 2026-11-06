// Adapted from SwiftCode-Legacy SwiftCode/Core/Build/BuildTargetInfo.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct BuildTargetInfo: Identifiable, Sendable, Codable {
    public var id: String { name }
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}
