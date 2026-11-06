import Foundation

public struct SCProjectRegistryEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let rootURL: URL
    public var lastOpened: Date
    public var lastModified: Date
    public var gitStatus: String
    public var swiftVersion: String
    public var packageStatus: String
    public var buildStatus: String
    public var description: String

    public init(id: UUID = UUID(), name: String, rootURL: URL, lastOpened: Date = Date(), lastModified: Date = Date(), gitStatus: String = "Clean", swiftVersion: String = "6.0", packageStatus: String = "Up to date", buildStatus: String = "Succeeded", description: String = "") {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.lastOpened = lastOpened
        self.lastModified = lastModified
        self.gitStatus = gitStatus
        self.swiftVersion = swiftVersion
        self.packageStatus = packageStatus
        self.buildStatus = buildStatus
        self.description = description
    }
}

public struct SCArchive: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let version: String
    public let buildNumber: String
    public let date: Date
    public let configuration: String
    public let commit: String
    public let binarySize: Int64
    public let symbolsAvailable: Bool
    public var releaseNotes: String

    public init(id: UUID = UUID(), projectName: String, version: String, buildNumber: String, date: Date = Date(), configuration: String = "Release", commit: String = "N/A", binarySize: Int64 = 0, symbolsAvailable: Bool = true, releaseNotes: String = "") {
        self.id = id
        self.projectName = projectName
        self.version = version
        self.buildNumber = buildNumber
        self.date = date
        self.configuration = configuration
        self.commit = commit
        self.binarySize = binarySize
        self.symbolsAvailable = symbolsAvailable
        self.releaseNotes = releaseNotes
    }
}

public struct SCBuildRecord: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let date: Date
    public let duration: TimeInterval
    public let warnings: Int
    public let errors: Int
    public let sdk: String
    public let destination: String
    public let configuration: String
    public let compiler: String
    public let logPath: String?
    public var status: String

    public init(id: UUID = UUID(), projectName: String, date: Date = Date(), duration: TimeInterval = 0, warnings: Int = 0, errors: Int = 0, sdk: String = "macosx", destination: String = "My Mac", configuration: String = "Debug", compiler: String = "swiftc", logPath: String? = nil, status: String = "Succeeded") {
        self.id = id
        self.projectName = projectName
        self.date = date
        self.duration = duration
        self.warnings = warnings
        self.errors = errors
        self.sdk = sdk
        self.destination = destination
        self.configuration = configuration
        self.compiler = compiler
        self.logPath = logPath
        self.status = status
    }
}

public struct SCBackup: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let projectName: String
    public let date: Date
    public let size: Int64
    public let path: String

    public init(id: UUID = UUID(), projectName: String, date: Date = Date(), size: Int64 = 0, path: String = "") {
        self.id = id
        self.projectName = projectName
        self.date = date
        self.size = size
        self.path = path
    }
}

public struct SCNotification: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let subtitle: String
    public let type: String // e.g. "Package", "Certificate", "Build", "Storage", "Diagnostics"
    public let date: Date
    public var isRead: Bool

    public init(id: UUID = UUID(), title: String, subtitle: String, type: String, date: Date = Date(), isRead: Bool = false) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.date = date
        self.isRead = isRead
    }
}
