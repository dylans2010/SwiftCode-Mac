import Foundation

public struct ExtensionIPCEnvelope: Codable, Sendable {
    public let id: String
    public let type: String
    public let target: String?
    public let payload: [String: String]?
    public let timestamp: Double

    public init(id: String = UUID().uuidString, type: String, target: String? = nil, payload: [String: String]? = nil, timestamp: Double = Date().timeIntervalSince1970) {
        self.id = id
        self.type = type
        self.target = target
        self.payload = payload
        self.timestamp = timestamp
    }
}

public enum ExtensionLifecycleEvent: String, Codable, Sendable {
    case ready = "extension.ready"
    case activated = "extension.activated"
    case deactivated = "extension.deactivated"
    case failed = "extension.failed"
}
