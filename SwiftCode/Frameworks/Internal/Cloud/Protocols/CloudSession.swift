import Foundation

public struct CloudDevice: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let lastActive: Date
    public let osVersion: String

    public init(id: String, name: String, lastActive: Date, osVersion: String) {
        self.id = id
        self.name = name
        self.lastActive = lastActive
        self.osVersion = osVersion
    }
}

public protocol CloudSession: AnyObject, Sendable {
    var sessionID: String? { get }
    var currentDeviceID: String { get }

    func registerDevice(name: String) async throws
    func getConnectedDevices() async throws -> [CloudDevice]
    func sendHeartbeat() async throws
}
