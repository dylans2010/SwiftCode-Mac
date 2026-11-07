import Foundation

public struct ConflictResolution: Identifiable, Codable, Equatable {
    public let id: UUID
    public let filePath: String
    public let currentContent: String
    public let incomingContent: String
    public var mergedResult: String?
    public var status: ResolutionStatus

    public enum ResolutionStatus: String, Codable {
        case pending
        case resolved
        case skipped
    }

    public init(filePath: String, current: String, incoming: String) {
        self.id = UUID()
        self.filePath = filePath
        self.currentContent = current
        self.incomingContent = incoming
        self.mergedResult = nil
        self.status = .pending
    }
}

@MainActor
public final class CollaborationConflictResolutionEngine: ObservableObject {
    @Published public private(set) var activeConflicts: [ConflictResolution] = []

    public func detectConflicts(current: [String: String], incoming: [String: String]) {
        activeConflicts.removeAll()
        for (path, incomingContent) in incoming {
            if let currentContent = current[path], currentContent != incomingContent {
                let resolution = ConflictResolution(filePath: path, current: currentContent, incoming: incomingContent)
                activeConflicts.append(resolution)
            }
        }
    }

    public func resolveConflict(id: UUID, with choice: ConflictResolutionChoice, manualContent: String? = nil) {
        guard let index = activeConflicts.firstIndex(where: { $0.id == id }) else { return }

        var conflict = activeConflicts[index]
        switch choice {
        case .useCurrent:
            conflict.mergedResult = conflict.currentContent
        case .useIncoming:
            conflict.mergedResult = conflict.incomingContent
        case .manual:
            conflict.mergedResult = manualContent
        }

        conflict.status = .resolved
        activeConflicts[index] = conflict
    }

    public var allResolved: Bool {
        activeConflicts.allSatisfy { $0.status == .resolved }
    }
}

public enum ConflictResolutionChoice: String, Codable, CaseIterable {
    case useCurrent
    case useIncoming
    case manual

    public var displayName: String {
        switch self {
        case .useCurrent: return "Current Changes"
        case .useIncoming: return "Incoming Changes"
        case .manual: return "Manual Edit"
        }
    }
}
