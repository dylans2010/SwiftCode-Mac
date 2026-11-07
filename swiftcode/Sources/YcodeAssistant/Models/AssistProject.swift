import Foundation

public struct AssistProject: Sendable, Codable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var directoryURL: URL
    public var githubRepo: String?
    public var customDirectoryPath: String?
    public var description: String?

    public init(name: String, directoryURL: URL = URL(fileURLWithPath: "/tmp"), githubRepo: String? = nil, description: String? = nil) {
        self.name = name
        self.directoryURL = directoryURL
        self.githubRepo = githubRepo
        self.description = description
    }

    public init(workspaceRoot: URL) {
        self.init(name: workspaceRoot.lastPathComponent, directoryURL: workspaceRoot)
    }
}

public typealias Project = AssistProject
