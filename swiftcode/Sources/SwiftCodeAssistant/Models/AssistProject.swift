import Foundation

public struct AssistProject: Sendable, Codable, Hashable {
    public let name: String
    public let directoryURL: URL
    public var githubRepo: String?

    public init(name: String, directoryURL: URL, githubRepo: String? = nil) {
        self.name = name
        self.directoryURL = directoryURL
        self.githubRepo = githubRepo
    }

    public init(workspaceRoot: URL) {
        self.init(name: workspaceRoot.lastPathComponent, directoryURL: workspaceRoot)
    }
}
