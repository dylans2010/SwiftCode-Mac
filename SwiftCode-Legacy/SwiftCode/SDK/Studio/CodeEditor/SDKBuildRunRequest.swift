import Foundation

public enum SDKBuildRunKind: String, Sendable, Codable, CaseIterable, Hashable {
    case xcodebuildSwift
    case typescriptExtension
    case nodeScript

    public var displayName: String {
        switch self {
        case .xcodebuildSwift: return "xcodebuild (Swift)"
        case .typescriptExtension: return "TypeScript Extension"
        case .nodeScript: return "Node Script"
        }
    }
}

public struct SDKBuildRunRequest: Identifiable, Sendable, Hashable {
    public let taskID: UUID

    public let projectRoot: URL

    public let kind: SDKBuildRunKind

    public let schemeOrEntry: String?

    public init(
        taskID: UUID = UUID(),
        projectRoot: URL,
        kind: SDKBuildRunKind,
        schemeOrEntry: String? = nil
    ) {
        self.taskID = taskID
        self.projectRoot = projectRoot
        self.kind = kind
        self.schemeOrEntry = schemeOrEntry
    }

    public var id: UUID { taskID }
}
