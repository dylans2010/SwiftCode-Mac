import Foundation

public struct VirtualMachineImage: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var operatingSystem: String
    public var version: String
    public var architecture: String
    public var fileLocation: String
    public var sizeBytes: Int64
    public var checksum: String
    public var downloadSource: String
    public var dateAdded: Date
    public var isInstalled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        operatingSystem: String,
        version: String,
        architecture: String = "ARM64",
        fileLocation: String = "",
        sizeBytes: Int64 = 0,
        checksum: String = "",
        downloadSource: String = "",
        dateAdded: Date = Date(),
        isInstalled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.operatingSystem = operatingSystem
        self.version = version
        self.architecture = architecture
        self.fileLocation = fileLocation
        self.sizeBytes = sizeBytes
        self.checksum = checksum
        self.downloadSource = downloadSource
        self.dateAdded = dateAdded
        self.isInstalled = isInstalled
    }
}
