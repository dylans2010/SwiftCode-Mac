import Foundation

#if canImport(AppKit)
import AppKit
#endif

public enum AssistAlertSound: Sendable {
    case agentThinking
    case agentResponseReady
    case agentNeedsAttention
}

public final class AlertSoundPlayer: @unchecked Sendable {
    public static let shared = AlertSoundPlayer()

    public var isEnabled = true

    private init() {}

    public func play(_ sound: AssistAlertSound) {
        guard isEnabled else { return }
        #if canImport(AppKit)
        let name: String
        switch sound {
        case .agentThinking: name = "Pop"
        case .agentResponseReady: name = "Glass"
        case .agentNeedsAttention: name = "Basso"
        }
        NSSound(named: NSSound.Name(name))?.play()
        #else
        _ = sound
        #endif
    }
}

public final class NotificationManager: @unchecked Sendable {
    public static let shared = NotificationManager()

    public var isEnabled = true

    private init() {}

    public func sendAgentTaskFinishedNotification(title: String = "Assist", body: String = "The task finished.") {
        guard isEnabled else { return }
        #if canImport(AppKit)
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        NSUserNotificationCenter.default.deliver(notification)
        #else
        _ = (title, body)
        #endif
    }
}
