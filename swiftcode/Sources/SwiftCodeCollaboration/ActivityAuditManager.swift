import Foundation

public struct ActivityEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let actorID: String
    public let action: String
    public let detail: String
    public let timestamp: Date
    public let kind: CollaborationActivity.Kind

    public init(actorID: String, action: String, detail: String, kind: CollaborationActivity.Kind) {
        self.id = UUID()
        self.actorID = actorID
        self.action = action
        self.detail = detail
        self.timestamp = Date()
        self.kind = kind
    }
}

@MainActor
public final class ActivityAuditManager: ObservableObject {
    @Published public private(set) var auditLog: [ActivityEntry] = []

    public func log(actorID: String, action: String, detail: String, kind: CollaborationActivity.Kind) {
        let entry = ActivityEntry(actorID: actorID, action: action, detail: detail, kind: kind)
        auditLog.insert(entry, at: 0)

        if auditLog.count > 1000 {
            auditLog.removeLast()
        }
    }

    public func filteredLog(user: String? = nil, kind: CollaborationActivity.Kind? = nil) -> [ActivityEntry] {
        auditLog.filter { entry in
            let userMatch = user == nil || entry.actorID == user
            let kindMatch = kind == nil || entry.kind == kind
            return userMatch && kindMatch
        }
    }
}
