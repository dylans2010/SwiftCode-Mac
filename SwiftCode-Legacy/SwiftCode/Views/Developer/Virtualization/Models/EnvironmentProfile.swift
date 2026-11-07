import Foundation

public struct EnvironmentProfile: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var targetOS: String
    public var attachedProjectIDs: [UUID]
    public var environmentVariables: [String: String]
    public var startupCommands: [String]
    public var installedPackages: [String]
    public var virtualMachineID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        targetOS: String,
        attachedProjectIDs: [UUID] = [],
        environmentVariables: [String: String] = [:],
        startupCommands: [String] = [],
        installedPackages: [String] = [],
        virtualMachineID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.targetOS = targetOS
        self.attachedProjectIDs = attachedProjectIDs
        self.environmentVariables = environmentVariables
        self.startupCommands = startupCommands
        self.installedPackages = installedPackages
        self.virtualMachineID = virtualMachineID
    }
}
