import Foundation

public struct SavedRepository: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var owner: String
    public var repositoryURL: String
    public var defaultBranch: String
    public var localProjectPath: String?

    public init(id: UUID = UUID(), name: String, owner: String, repositoryURL: String, defaultBranch: String = "main", localProjectPath: String? = nil) {
        self.id = id
        self.name = name
        self.owner = owner
        self.repositoryURL = repositoryURL
        self.defaultBranch = defaultBranch
        self.localProjectPath = localProjectPath
    }
}

public enum DashboardLayout: String, Codable, CaseIterable, Sendable {
    case grid = "Grid"
    case list = "List"
}

public enum DashboardSortOrder: String, Codable, CaseIterable, Sendable {
    case name = "Name"
    case lastOpened = "Last Opened"
    case creationDate = "Creation Date"
}

public enum FileNavigatorLayoutStyle: String, Codable, CaseIterable, Sendable {
    case compact = "Compact"
    case expanded = "Expanded"
}

public enum FileNavigatorAnimationStyle: String, Codable, CaseIterable, Sendable {
    case easeInOut = "Ease In/Out"
    case spring = "Spring"
    case bouncy = "Bouncy"
}
