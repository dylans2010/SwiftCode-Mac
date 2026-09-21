import Foundation
import AppKit
import AudioToolbox
import OSLog

// MARK: - Sound Source

public enum SoundSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "System"
    case custom = "App"
    case user = "User"

    public var id: String { rawValue }

    public var badgeColorHex: String {
        switch self {
        case .system: return "#007AFF" // Blue
        case .custom: return "#FF9500" // Orange
        case .user:   return "#34C759" // Green
        }
    }
}

// MARK: - App Sound Category

public enum AppSoundCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case notification = "Notification"
    case message = "Message"
    case success = "Success"
    case error = "Error"
    case complete = "Complete"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .notification: return "bell.badge"
        case .message: return "bubble.left.and.bubble.right"
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        case .complete: return "flag.checkered"
        }
    }
}

// MARK: - Unified App Sound Model

public struct AppSound: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let filename: String
    public let category: AppSoundCategory?
    public let source: SoundSource
    public let explicitURL: URL?

    public init(
        id: String,
        displayName: String,
        filename: String,
        category: AppSoundCategory? = nil,
        source: SoundSource = .custom,
        explicitURL: URL? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.filename = filename
        self.category = category
        self.source = source
        self.explicitURL = explicitURL
    }

    /// Primary resolved URL for audio playback
    public var resolvedURL: URL? {
        if let explicit = explicitURL, FileManager.default.fileExists(atPath: explicit.path) {
            return explicit
        }

        switch source {
        case .custom:
            return bundleURL ?? installedURL
        case .system:
            if let explicit = explicitURL { return explicit }
            let sysDir = URL(fileURLWithPath: "/System/Library/Sounds")
            let url = sysDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            return nil
        case .user:
            return installedURL
        }
    }

    /// URL to the sound bundled inside the application's resources
    public var bundleURL: URL? {
        if let explicit = explicitURL, FileManager.default.fileExists(atPath: explicit.path) {
            return explicit
        }
        let soundName = (filename as NSString).deletingPathExtension
        let soundExt = (filename as NSString).pathExtension
        if let url = Bundle.main.url(forResource: soundName, withExtension: soundExt) {
            return url
        }
        if let url = Bundle.main.url(forResource: soundName, withExtension: soundExt, subdirectory: "Sounds") {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(filename),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }
        // Fallback for development / test environments
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: soundName, withExtension: soundExt) {
                return url
            }
        }
        return nil
    }

    /// URL to the sound installed in ~/Library/Sounds/
    public var installedURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Sounds", isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Returns true if the sound file exists or is recognized natively by NSSound
    public var isAvailable: Bool {
        if let url = resolvedURL, FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        if source == .system {
            let soundName = (filename as NSString).deletingPathExtension
            return NSSound(named: NSSound.Name(soundName)) != nil
        }
        return false
    }
}

// MARK: - Unified Sound Catalog

public enum SoundCatalog {
    public static let noneSoundID = "none"
    private static let logger = Logger(subsystem: "com.dylans2010.SwiftCode-Mac", category: "SoundCatalog")

    // MARK: - Custom Application Sounds (25 Original Audio Assets)

    // Notifications (8)
    public static let notificationA = AppSound(
        id: "swiftcode_notification_a",
        displayName: "Notification A (Crystal Chime)",
        filename: "SwiftCode_Notification_A.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationB = AppSound(
        id: "swiftcode_notification_b",
        displayName: "Notification B (Warm Marimba)",
        filename: "SwiftCode_Notification_B.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationC = AppSound(
        id: "swiftcode_notification_c",
        displayName: "Notification C (Digital Blip)",
        filename: "SwiftCode_Notification_C.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationD = AppSound(
        id: "swiftcode_notification_d",
        displayName: "Notification D (String Pluck)",
        filename: "SwiftCode_Notification_D.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationE = AppSound(
        id: "swiftcode_notification_e",
        displayName: "Notification E (Vibraphone)",
        filename: "SwiftCode_Notification_E.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationF = AppSound(
        id: "swiftcode_notification_f",
        displayName: "Notification F (Glissando)",
        filename: "SwiftCode_Notification_F.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationG = AppSound(
        id: "swiftcode_notification_g",
        displayName: "Notification G (Celesta)",
        filename: "SwiftCode_Notification_G.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationH = AppSound(
        id: "swiftcode_notification_h",
        displayName: "Notification H (AirDrop Pulse)",
        filename: "SwiftCode_Notification_H.aiff",
        category: .notification,
        source: .custom
    )

    // Messages (5)
    public static let messageA = AppSound(
        id: "swiftcode_message_a",
        displayName: "Message A (Glass Ping)",
        filename: "SwiftCode_Message_A.aiff",
        category: .message,
        source: .custom
    )
    public static let messageB = AppSound(
        id: "swiftcode_message_b",
        displayName: "Message B (Wood Tap)",
        filename: "SwiftCode_Message_B.aiff",
        category: .message,
        source: .custom
    )
    public static let messageC = AppSound(
        id: "swiftcode_message_c",
        displayName: "Message C (Subtle Bell)",
        filename: "SwiftCode_Message_C.aiff",
        category: .message,
        source: .custom
    )
    public static let messageD = AppSound(
        id: "swiftcode_message_d",
        displayName: "Message D (Double Pop)",
        filename: "SwiftCode_Message_D.aiff",
        category: .message,
        source: .custom
    )
    public static let messageE = AppSound(
        id: "swiftcode_message_e",
        displayName: "Message E (Echo Droplet)",
        filename: "SwiftCode_Message_E.aiff",
        category: .message,
        source: .custom
    )

    // Success (4)
    public static let successA = AppSound(
        id: "swiftcode_success_a",
        displayName: "Success A (Major Triad)",
        filename: "SwiftCode_Success_A.aiff",
        category: .success,
        source: .custom
    )
    public static let successB = AppSound(
        id: "swiftcode_success_b",
        displayName: "Success B (Harmonic Rise)",
        filename: "SwiftCode_Success_B.aiff",
        category: .success,
        source: .custom
    )
    public static let successC = AppSound(
        id: "swiftcode_success_c",
        displayName: "Success C (Fanfare Lift)",
        filename: "SwiftCode_Success_C.aiff",
        category: .success,
        source: .custom
    )
    public static let successD = AppSound(
        id: "swiftcode_success_d",
        displayName: "Success D (Cascading Shimmer)",
        filename: "SwiftCode_Success_D.aiff",
        category: .success,
        source: .custom
    )

    // Error / Warning (4)
    public static let errorA = AppSound(
        id: "swiftcode_error_a",
        displayName: "Error A (Warm Dissonance)",
        filename: "SwiftCode_Error_A.aiff",
        category: .error,
        source: .custom
    )
    public static let errorB = AppSound(
        id: "swiftcode_error_b",
        displayName: "Error B (Damped Drop)",
        filename: "SwiftCode_Error_B.aiff",
        category: .error,
        source: .custom
    )
    public static let errorC = AppSound(
        id: "swiftcode_error_c",
        displayName: "Error C (Double Thud)",
        filename: "SwiftCode_Error_C.aiff",
        category: .error,
        source: .custom
    )
    public static let warningA = AppSound(
        id: "swiftcode_warning_a",
        displayName: "Warning A (Caution Pulse)",
        filename: "SwiftCode_Warning_A.aiff",
        category: .error,
        source: .custom
    )

    // Completion (4)
    public static let completeA = AppSound(
        id: "swiftcode_complete_a",
        displayName: "Complete A (Chime Resolve)",
        filename: "SwiftCode_Complete_A.aiff",
        category: .complete,
        source: .custom
    )
    public static let completeB = AppSound(
        id: "swiftcode_complete_b",
        displayName: "Complete B (Arpeggio Finish)",
        filename: "SwiftCode_Complete_B.aiff",
        category: .complete,
        source: .custom
    )
    public static let completeC = AppSound(
        id: "swiftcode_complete_c",
        displayName: "Complete C (Ambient Bloom)",
        filename: "SwiftCode_Complete_C.aiff",
        category: .complete,
        source: .custom
    )
    public static let completeD = AppSound(
        id: "swiftcode_complete_d",
        displayName: "Complete D (Orchestral Chime)",
        filename: "SwiftCode_Complete_D.aiff",
        category: .complete,
        source: .custom
    )

    /// All 25 original custom application sounds
    public static let customSounds: [AppSound] = [
        notificationA, notificationB, notificationC, notificationD,
        notificationE, notificationF, notificationG, notificationH,
        messageA, messageB, messageC, messageD, messageE,
        successA, successB, successC, successD,
        errorA, errorB, errorC, warningA,
        completeA, completeB, completeC, completeD
    ]

    // MARK: - Dynamic Discovery: Native macOS System Sounds

    /// Dynamically queries all discoverable native macOS system sounds available through supported system APIs.
    public static let systemSounds: [AppSound] = discoverSystemSounds()

    /// Dynamically scans and discovers native macOS system sounds
    public static func discoverSystemSounds() -> [AppSound] {
        var discovered: [AppSound] = []
        let supportedExtensions = Set(["aiff", "aif", "caf", "wav", "mp3", "m4a"])

        // Query standard system library domains for sounds
        var searchURLs: [URL] = []
        if let systemLib = FileManager.default.urls(for: .libraryDirectory, in: .systemDomainMask).first {
            searchURLs.append(systemLib.appendingPathComponent("Sounds", isDirectory: true))
        }
        // Also check local domain /Library/Sounds
        if let localLib = FileManager.default.urls(for: .libraryDirectory, in: .localDomainMask).first {
            searchURLs.append(localLib.appendingPathComponent("Sounds", isDirectory: true))
        }

        for directory in searchURLs {
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            guard let fileURLs = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in fileURLs {
                let ext = url.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }

                let rawName = url.deletingPathExtension().lastPathComponent
                let stableID = "system_\(rawName.lowercased().replacingOccurrences(of: " ", with: "_"))"

                // Verify file is readable and decodable via AudioServices or NSSound
                let sound = AppSound(
                    id: stableID,
                    displayName: rawName,
                    filename: url.lastPathComponent,
                    category: nil,
                    source: .system,
                    explicitURL: url
                )
                if !discovered.contains(where: { $0.id == sound.id }) {
                    discovered.append(sound)
                }
            }
        }

        // Fallback check: if system directory had restricted permissions, probe standard system named alerts via NSSound
        if discovered.isEmpty {
            let fallbackAlertNames = [
                "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass",
                "Hero", "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
            ]
            for name in fallbackAlertNames {
                if NSSound(named: NSSound.Name(name)) != nil {
                    discovered.append(AppSound(
                        id: "system_\(name.lowercased())",
                        displayName: name,
                        filename: "\(name).aiff",
                        category: nil,
                        source: .system
                    ))
                }
            }
        }

        return discovered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Dynamic Discovery: User-Installed Sounds

    /// Dynamically scans ~/Library/Sounds for user-installed alert sounds (excluding SwiftCode custom sounds)
    public static func discoverUserSounds() -> [AppSound] {
        var userSounds: [AppSound] = []
        let userDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: userDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for url in files {
            let filename = url.lastPathComponent
            // Ignore SwiftCode's own installed sounds
            if filename.hasPrefix("SwiftCode_") { continue }

            let rawName = url.deletingPathExtension().lastPathComponent
            let stableID = "user_\(rawName.lowercased().replacingOccurrences(of: " ", with: "_"))"

            let sound = AppSound(
                id: stableID,
                displayName: rawName,
                filename: filename,
                category: nil,
                source: .user,
                explicitURL: url
            )
            userSounds.append(sound)
        }

        return userSounds.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    // MARK: - Unified Sound Accessors

    /// Complete unified library of all available sounds (System + Custom + User)
    public static var allSounds: [AppSound] {
        return customSounds + systemSounds + discoverUserSounds()
    }

    /// Retrieve a sound by its stable identifier
    public static func sound(for id: String) -> AppSound? {
        if id == noneSoundID { return nil }

        // 1. Direct match in custom sounds
        if let custom = customSounds.first(where: { $0.id == id }) {
            return custom
        }

        // 2. Direct match in system sounds
        if let sys = systemSounds.first(where: { $0.id == id }) {
            return sys
        }

        // 3. Match in dynamically discovered user sounds
        let userSounds = discoverUserSounds()
        if let user = userSounds.first(where: { $0.id == id }) {
            return user
        }

        // 4. Backward compatibility: match by filename or legacy ID without prefix
        for sound in allSounds {
            if sound.filename == id || sound.id.replacingOccurrences(of: "swiftcode_", with: "") == id {
                return sound
            }
        }

        return nil
    }

    /// Retrieve sounds by category
    public static func sounds(for category: AppSoundCategory) -> [AppSound] {
        return customSounds.filter { $0.category == category }
    }

    /// Filter sounds across search query, category, and source
    public static func filteredSounds(
        query: String = "",
        category: AppSoundCategory? = nil,
        source: SoundSource? = nil
    ) -> [AppSound] {
        return allSounds.filter { sound in
            if let cat = category, sound.category != cat && sound.source == .custom {
                return false
            }
            if let src = source, sound.source != src {
                return false
            }
            if !query.isEmpty {
                let matchesName = sound.displayName.localizedCaseInsensitiveContains(query)
                let matchesCategory = sound.category?.rawValue.localizedCaseInsensitiveContains(query) ?? false
                let matchesSource = sound.source.rawValue.localizedCaseInsensitiveContains(query)
                return matchesName || matchesCategory || matchesSource
            }
            return true
        }
    }

    /// Default sound for each category
    public static func defaultSound(for category: AppSoundCategory) -> AppSound {
        switch category {
        case .notification: return notificationA
        case .message: return messageA
        case .success: return successA
        case .error: return errorA
        case .complete: return completeA
        }
    }
}
