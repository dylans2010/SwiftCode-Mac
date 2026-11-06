import Foundation

public struct EnvironmentProfile: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var targetOS: String // Operating system name, e.g. Ubuntu
    public var attachedProjectIDs: [UUID] // projects configured to use this profile
    public var environmentVariables: [String: String] // env vars configured inside the container
    public var startupCommands: [String] // commands run on start, e.g. ["npm install", "swift build"]
    public var installedPackages: [String] // list of software packages required, e.g. ["git", "node", "swift"]
    public var virtualMachineID: UUID? // associated VM that runs this environment

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
