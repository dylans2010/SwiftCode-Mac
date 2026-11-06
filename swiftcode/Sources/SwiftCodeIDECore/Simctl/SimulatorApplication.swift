// Adapted from SwiftCode-Legacy SwiftCode/Core/Simulator/SimulatorApplication.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct SimulatorApplication: Identifiable, Hashable, Codable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let name: String
    public let path: String
    public let version: String
    public let targetPlatform: String

    public init(bundleIdentifier: String, name: String, path: String, version: String, targetPlatform: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.version = version
        self.targetPlatform = targetPlatform
    }
}
