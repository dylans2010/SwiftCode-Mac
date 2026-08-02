import Foundation
import UserNotifications
import OSLog

public final class NotificationService: Sendable {
    public static let shared = NotificationService()
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "NotificationService")

    private init() {}

    public func postNotification(title: String, subtitle: String = "", body: String) {
        Self.logger.info("Notification triggered: \(title) - \(body)")

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Self.logger.error("Failed to post system notification: \(error.localizedDescription)")
            }
        }
    }
}
