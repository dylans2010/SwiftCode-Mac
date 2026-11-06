import Foundation
import UserNotifications
import AppKit

/// Tool for posting genuine macOS system notifications and alerts for long-running Assist tasks or build completions.
public struct AssistSystemNotificationTool: AssistTool {
    public let id = "system_notification_tool"
    public let name = "Post macOS System Notification"
    public let description = "Posts a genuine macOS system notification banner or alert with custom title, subtitle, sound, and message body for build status, task completions, or developer alerts."
    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let arguments = input
        let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "SwiftCode Assist"
        let subtitle = (arguments["subtitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = (arguments["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (arguments["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Task completed."
        let soundName = arguments["sound"] as? String ?? "default" // "default", "none", or sound file name
        let isCritical = arguments["critical"] as? Bool ?? false

        // Check if UserNotifications authorization is available, otherwise deliver via osascript AppleScript fallback
        let center = UNUserNotificationCenter.current()
        var deliveredViaUN = false
        var authStatusDescription = "unknown"

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            let content = UNMutableNotificationContent()
            content.title = title
            if !subtitle.isEmpty {
                content.subtitle = subtitle
            }
            content.body = message
            if soundName.lowercased() != "none" {
                content.sound = isCritical ? UNNotificationSound.defaultCritical : UNNotificationSound.default
            }
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
                deliveredViaUN = true
                authStatusDescription = "authorized"
            } catch {
                authStatusDescription = "failed: \(error.localizedDescription)"
            }
        case .denied:
            authStatusDescription = "denied"
        case .notDetermined:
            // Request authorization
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    if !subtitle.isEmpty {
                        content.subtitle = subtitle
                    }
                    content.body = message
                    if soundName.lowercased() != "none" {
                        content.sound = .default
                    }
                    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    try await center.add(req)
                    deliveredViaUN = true
                    authStatusDescription = "granted_and_delivered"
                } else {
                    authStatusDescription = "not_granted"
                }
            } catch {
                authStatusDescription = "auth_error: \(error.localizedDescription)"
            }
        @unknown default:
            authStatusDescription = "unknown_status"
        }

        // If UNNotificationCenter was not delivered (e.g. ad-hoc signed or denied in CLI environment), trigger AppleScript notification fallback
        var scriptDelivered = false
        if !deliveredViaUN {
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedSubtitle = subtitle.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedBody = message.replacingOccurrences(of: "\"", with: "\\\"")
            
            var scriptText = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
            if !escapedSubtitle.isEmpty {
                scriptText += " subtitle \"\(escapedSubtitle)\""
            }
            if soundName.lowercased() != "none" {
                scriptText += " sound name \"Submarine\""
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", scriptText]
            do {
                try process.run()
                process.waitUntilExit()
                scriptDelivered = process.terminationStatus == 0
            } catch {
                scriptDelivered = false
            }
        }

        let outputSummary = """
        System Notification Delivered:
        - Title: \(title)
        - Subtitle: \(subtitle.isEmpty ? "None" : subtitle)
        - Message: \(message)
        - Native UNUserNotification: \(deliveredViaUN ? "Success" : "Bypassed (\(authStatusDescription))")
        - AppleScript Notification Fallback: \(scriptDelivered ? "Success" : (deliveredViaUN ? "Not needed" : "Failed"))
        - Sound: \(soundName)
        - Timestamp: \(ISO8601DateFormatter().string(from: Date()))
        """

        return AssistToolResult(
            success: (deliveredViaUN || scriptDelivered),
            output: outputSummary
        )
    }
}
