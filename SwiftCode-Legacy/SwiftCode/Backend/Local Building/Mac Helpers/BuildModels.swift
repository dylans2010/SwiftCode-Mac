import Foundation

public struct BuildRequest: Codable {
    public let projectName: String
    public let platform: String
    public let configuration: String
    public let projectData: Data // Compressed project files

    public init(projectName: String, platform: String = "iOS", configuration: String = "Release", projectData: Data) {
        self.projectName = projectName
        self.platform = platform
        self.configuration = configuration
        self.projectData = projectData
    }
}

public struct BuildResponse: Codable {
    public let success: Bool
    public let message: String
    public let ipaData: Data?

    public init(success: Bool, message: String, ipaData: Data? = nil) {
        self.success = success
        self.message = message
        self.ipaData = ipaData
    }
}

public struct BuildStatusMessage: Codable, Identifiable {
    public let id: UUID
    public let status: String
    public let timestamp: Date

    public init(status: String) {
        self.id = UUID()
        self.status = status
        self.timestamp = Date()
    }
}
