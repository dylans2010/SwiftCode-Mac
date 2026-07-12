import Foundation

public struct SimulatorRuntime: Identifiable, Hashable, Codable, Sendable {
    public var id: String { identifier }
    public let identifier: String
    public let name: String
    public let version: String
    public let platform: String // iOS, watchOS, tvOS, visionOS, macOS
    public let isAvailable: Bool

    public init(identifier: String, name: String, version: String, platform: String, isAvailable: Bool = true) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.platform = platform
        self.isAvailable = isAvailable
    }
}
