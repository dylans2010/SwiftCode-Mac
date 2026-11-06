import Foundation
import AppKit
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }

            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                if let error {
                    print("[NotificationManager] Failed to request authorization: \(error)")
                    return
                }

                print("[NotificationManager] Notifications authorization granted: \(granted)")
            }
        }
    }

    func sendOfflineModelDownloadedNotification(modelName: String) {
        scheduleNotification(
            identifier: "offline-model-downloaded-\(UUID().uuidString)",
            title: "Model Download Complete",
            body: "\(modelName) has been downloaded and is ready to use.",
            category: .success
        )
    }

    func sendAgentTaskFinishedNotification() {
        scheduleNotification(
            identifier: "agent-task-complete-\(UUID().uuidString)",
            title: "Task Complete",
            body: "The agent has finished processing your request.",
            category: .complete
        )
    }

    public func scheduleNotification(identifier: String, title: String, body: String, category: AppSoundCategory = .notification) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let soundID: String
        switch category {
        case .notification:
            soundID = AppSettings.shared.notificationSoundID
        case .message:
            soundID = AppSettings.shared.messageSoundID
        case .success:
            soundID = AppSettings.shared.successSoundID
        case .error:
            soundID = AppSettings.shared.errorSoundID
        case .complete:
            soundID = AppSettings.shared.completionSoundID
        case .chill:
            soundID = SoundCatalog.chillSoftBloom.id
        case .vibe:
            soundID = SoundCatalog.vibePulse.id
        case .satisfying:
            soundID = SoundCatalog.satisfyingPerfect.id
        }

        if soundID == SoundCatalog.noneSoundID {
            content.sound = nil
        } else if let appSound = SoundCatalog.sound(for: soundID) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(appSound.filename))
        } else {
            content.sound = .default
        }

        // If the application is active in the foreground, also play immediately through AlertSoundPlayer
        if NSApplication.shared.isActive {
            let tone: AlertTone
            switch category {
            case .notification: tone = .mention
            case .message:      tone = .messageReceived
            case .success:      tone = .buildSuccess
            case .error:        tone = .error
            case .complete:     tone = .taskComplete
            case .chill, .vibe, .satisfying: tone = .syncComplete
            }
            AlertSoundPlayer.shared.play(tone)
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[NotificationManager] Failed to schedule notification: \(error)")
            }
        }
    }
}
