import Foundation
import Combine

public struct CollaborationNotification: Identifiable, Codable, Equatable {
    public let id: UUID
    public let title: String
    public let body: String
    public let timestamp: Date
    public var isRead: Bool
    public let category: NotificationCategory

    public enum NotificationCategory: String, Codable {
        case mention
        case pullRequest
        case comment
        case sync
    }

    public init(title: String, body: String, category: NotificationCategory, isRead: Bool = false) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.timestamp = Date()
        self.isRead = isRead
        self.category = category
    }
}

@MainActor
public final class CollaborationNotificationManager: ObservableObject {
    @Published public private(set) var notifications: [CollaborationNotification] = []

    public func addNotification(title: String, body: String, category: CollaborationNotification.NotificationCategory) {
        let notification = CollaborationNotification(title: title, body: body, category: category)
        notifications.insert(notification, at: 0)

        // Potential for local notification push here
    }

    public func markAsRead(_ id: UUID) {
        if let index = notifications.firstIndex(where: { $0.id == id }) {
            notifications[index].isRead = true
        }
    }

    public func clearAll() {
        notifications.removeAll()
    }

    public var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }
}
