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
        case .system: return "#007AFF" // System Blue
        case .custom: return "#FF9500" // Warm Amber / Orange
        case .user:   return "#34C759" // Nature Green
        }
    }
}

// MARK: - App Sound Category

public enum AppSoundCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case chill        = "Chill"
    case vibe         = "Vibe"
    case satisfying   = "Satisfying"
    case success      = "Success"
    case complete     = "Completion"
    case message      = "Message"
    case notification = "Notification"
    case error        = "Error / Warning"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .chill:        return "sparkles"
        case .vibe:         return "waveform.path"
        case .satisfying:   return "heart.circle.fill"
        case .success:      return "checkmark.circle.fill"
        case .complete:     return "flag.checkered"
        case .message:      return "bubble.left.and.bubble.right.fill"
        case .notification: return "bell.badge.fill"
        case .error:        return "exclamationmark.triangle.fill"
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

    /// Primary resolved URL for audio playback, guaranteed to point to an existing file if one is found
    public var resolvedURL: URL? {
        if let explicit = explicitURL, FileManager.default.fileExists(atPath: explicit.path) {
            return explicit
        }

        switch source {
        case .custom:
            // 1. Check bundle URL
            if let bundle = bundleURL, FileManager.default.fileExists(atPath: bundle.path) {
                return bundle
            }
            // 2. Check ~/Library/Sounds/
            if FileManager.default.fileExists(atPath: installedURL.path) {
                return installedURL
            }
            // 3. Check development source repo
            if let repoURL = devRepoURL, FileManager.default.fileExists(atPath: repoURL.path) {
                return repoURL
            }
            return nil

        case .system:
            if let explicit = explicitURL, FileManager.default.fileExists(atPath: explicit.path) {
                return explicit
            }
            let sysDir = URL(fileURLWithPath: "/System/Library/Sounds")
            let url = sysDir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            return nil

        case .user:
            if FileManager.default.fileExists(atPath: installedURL.path) {
                return installedURL
            }
            return nil
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

    /// URL to the sound in the project development source directory (for Xcode debug/previews)
    public var devRepoURL: URL? {
        let repoSound = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // SwiftCode
            .appendingPathComponent("Resources/Sounds/\(filename)")
        if FileManager.default.fileExists(atPath: repoSound.path) {
            return repoSound
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
        let soundName = (filename as NSString).deletingPathExtension
        return NSSound(named: NSSound.Name(soundName)) != nil
    }
}

// MARK: - Unified Sound Catalog

public enum SoundCatalog {
    public static let noneSoundID = "none"
    private static let logger = Logger(subsystem: "com.dylans2010.SwiftCode-Mac", category: "SoundCatalog")

    // =========================================================================
    // 32 Original Cinematic Micro-Sounds
    // =========================================================================

    // MARK: - Category: Chill (6)
    public static let chillSoftBloom = AppSound(
        id: "custom.chill.soft_bloom",
        displayName: "Soft Bloom",
        filename: "SwiftCode_Chill_SoftBloom.aiff",
        category: .chill,
        source: .custom
    )
    public static let chillCloud = AppSound(
        id: "custom.chill.cloud",
        displayName: "Cloud",
        filename: "SwiftCode_Chill_Cloud.aiff",
        category: .chill,
        source: .custom
    )
    public static let chillDrift = AppSound(
        id: "custom.chill.drift",
        displayName: "Drift",
        filename: "SwiftCode_Chill_Drift.aiff",
        category: .chill,
        source: .custom
    )
    public static let chillVelvet = AppSound(
        id: "custom.chill.velvet",
        displayName: "Velvet",
        filename: "SwiftCode_Chill_Velvet.aiff",
        category: .chill,
        source: .custom
    )
    public static let chillAmbientRise = AppSound(
        id: "custom.chill.ambient_rise",
        displayName: "Ambient Rise",
        filename: "SwiftCode_Chill_AmbientRise.aiff",
        category: .chill,
        source: .custom
    )
    public static let chillCalmBell = AppSound(
        id: "custom.chill.calm_bell",
        displayName: "Calm Bell",
        filename: "SwiftCode_Chill_CalmBell.aiff",
        category: .chill,
        source: .custom
    )

    // MARK: - Category: Vibe (6)
    public static let vibePulse = AppSound(
        id: "custom.vibe.pulse",
        displayName: "Pulse",
        filename: "SwiftCode_Vibe_Pulse.aiff",
        category: .vibe,
        source: .custom
    )
    public static let vibeGlow = AppSound(
        id: "custom.vibe.glow",
        displayName: "Glow",
        filename: "SwiftCode_Vibe_Glow.aiff",
        category: .vibe,
        source: .custom
    )
    public static let vibeWave = AppSound(
        id: "custom.vibe.wave",
        displayName: "Wave",
        filename: "SwiftCode_Vibe_Wave.aiff",
        category: .vibe,
        source: .custom
    )
    public static let vibeNeon = AppSound(
        id: "custom.vibe.neon",
        displayName: "Neon",
        filename: "SwiftCode_Vibe_Neon.aiff",
        category: .vibe,
        source: .custom
    )
    public static let vibeFlux = AppSound(
        id: "custom.vibe.flux",
        displayName: "Flux",
        filename: "SwiftCode_Vibe_Flux.aiff",
        category: .vibe,
        source: .custom
    )
    public static let vibeEcho = AppSound(
        id: "custom.vibe.echo",
        displayName: "Echo",
        filename: "SwiftCode_Vibe_Echo.aiff",
        category: .vibe,
        source: .custom
    )

    // MARK: - Category: Satisfying (6)
    public static let satisfyingPerfect = AppSound(
        id: "custom.satisfying.perfect",
        displayName: "Perfect",
        filename: "SwiftCode_Satisfying_Perfect.aiff",
        category: .satisfying,
        source: .custom
    )
    public static let satisfyingSpark = AppSound(
        id: "custom.satisfying.spark",
        displayName: "Spark",
        filename: "SwiftCode_Satisfying_Spark.aiff",
        category: .satisfying,
        source: .custom
    )
    public static let satisfyingResolve = AppSound(
        id: "custom.satisfying.resolve",
        displayName: "Resolve",
        filename: "SwiftCode_Satisfying_Resolve.aiff",
        category: .satisfying,
        source: .custom
    )
    public static let satisfyingClickBloom = AppSound(
        id: "custom.satisfying.click_bloom",
        displayName: "Click Bloom",
        filename: "SwiftCode_Satisfying_ClickBloom.aiff",
        category: .satisfying,
        source: .custom
    )
    public static let satisfyingVelvetPop = AppSound(
        id: "custom.satisfying.velvet_pop",
        displayName: "Velvet Pop",
        filename: "SwiftCode_Satisfying_VelvetPop.aiff",
        category: .satisfying,
        source: .custom
    )
    public static let satisfyingSoftChime = AppSound(
        id: "custom.satisfying.soft_chime",
        displayName: "Soft Chime",
        filename: "SwiftCode_Satisfying_SoftChime.aiff",
        category: .satisfying,
        source: .custom
    )

    // MARK: - Category: Success (4)
    public static let successComplete = AppSound(
        id: "custom.success.complete",
        displayName: "Complete",
        filename: "SwiftCode_Success_Complete.aiff",
        category: .success,
        source: .custom
    )
    public static let successConfirmed = AppSound(
        id: "custom.success.confirmed",
        displayName: "Confirmed",
        filename: "SwiftCode_Success_Confirmed.aiff",
        category: .success,
        source: .custom
    )
    public static let successReady = AppSound(
        id: "custom.success.ready",
        displayName: "Ready",
        filename: "SwiftCode_Success_Ready.aiff",
        category: .success,
        source: .custom
    )
    public static let successDone = AppSound(
        id: "custom.success.done",
        displayName: "Done",
        filename: "SwiftCode_Success_Done.aiff",
        category: .success,
        source: .custom
    )

    // MARK: - Category: Message (4)
    public static let messageMessage = AppSound(
        id: "custom.message.message",
        displayName: "Message",
        filename: "SwiftCode_Message_Message.aiff",
        category: .message,
        source: .custom
    )
    public static let messageWhisper = AppSound(
        id: "custom.message.whisper",
        displayName: "Whisper",
        filename: "SwiftCode_Message_Whisper.aiff",
        category: .message,
        source: .custom
    )
    public static let messagePresence = AppSound(
        id: "custom.message.presence",
        displayName: "Presence",
        filename: "SwiftCode_Message_Presence.aiff",
        category: .message,
        source: .custom
    )
    public static let messagePing = AppSound(
        id: "custom.message.ping",
        displayName: "Ping",
        filename: "SwiftCode_Message_Ping.aiff",
        category: .message,
        source: .custom
    )

    // MARK: - Category: Notification (4)
    public static let notificationSoftNotify = AppSound(
        id: "custom.notification.soft_notify",
        displayName: "Soft Notify",
        filename: "SwiftCode_Notification_SoftNotify.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationSignal = AppSound(
        id: "custom.notification.signal",
        displayName: "Signal",
        filename: "SwiftCode_Notification_Signal.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationRipple = AppSound(
        id: "custom.notification.ripple",
        displayName: "Ripple",
        filename: "SwiftCode_Notification_Ripple.aiff",
        category: .notification,
        source: .custom
    )
    public static let notificationArrival = AppSound(
        id: "custom.notification.arrival",
        displayName: "Arrival",
        filename: "SwiftCode_Notification_Arrival.aiff",
        category: .notification,
        source: .custom
    )

    // MARK: - Category: Error & Warning (2)
    public static let warningCaution = AppSound(
        id: "custom.warning.caution",
        displayName: "Caution",
        filename: "SwiftCode_Warning_Caution.aiff",
        category: .error,
        source: .custom
    )
    public static let errorAttention = AppSound(
        id: "custom.error.attention",
        displayName: "Attention",
        filename: "SwiftCode_Error_Attention.aiff",
        category: .error,
        source: .custom
    )

    // =========================================================================
    // Backward Compatibility Aliases for Legacy Sound References
    // =========================================================================
    public static let notificationA = chillSoftBloom
    public static let notificationB = chillCloud
    public static let notificationC = vibePulse
    public static let notificationD = satisfyingPerfect
    public static let notificationE = notificationSoftNotify
    public static let notificationF = notificationRipple
    public static let notificationG = chillCalmBell
    public static let notificationH = notificationSignal

    public static let messageA = messageMessage
    public static let messageB = satisfyingClickBloom
    public static let messageC = messagePing
    public static let messageD = satisfyingVelvetPop
    public static let messageE = messageWhisper

    public static let successA = successComplete
    public static let successB = successConfirmed
    public static let successC = successReady
    public static let successD = successDone

    public static let errorA = errorAttention
    public static let errorB = warningCaution
    public static let errorC = warningCaution
    public static let warningA = warningCaution

    public static let completeA = successComplete
    public static let completeB = satisfyingResolve
    public static let completeC = chillAmbientRise
    public static let completeD = satisfyingSoftChime

    /// All 32 original custom application sounds
    public static let customSounds: [AppSound] = [
        // Chill (6)
        chillSoftBloom, chillCloud, chillDrift, chillVelvet, chillAmbientRise, chillCalmBell,
        // Vibe (6)
        vibePulse, vibeGlow, vibeWave, vibeNeon, vibeFlux, vibeEcho,
        // Satisfying (6)
        satisfyingPerfect, satisfyingSpark, satisfyingResolve, satisfyingClickBloom, satisfyingVelvetPop, satisfyingSoftChime,
        // Success (4)
        successComplete, successConfirmed, successReady, successDone,
        // Message (4)
        messageMessage, messageWhisper, messagePresence, messagePing,
        // Notification (4)
        notificationSoftNotify, notificationSignal, notificationRipple, notificationArrival,
        // Warning / Error (2)
        warningCaution, errorAttention
    ]

    // MARK: - Dynamic Discovery: Native macOS System Sounds

    /// Dynamically discovered native macOS system sounds available on this Mac
    public static let systemSounds: [AppSound] = discoverSystemSounds()

    /// Dynamically scans and discovers native macOS system sounds from /System/Library/Sounds
    public static func discoverSystemSounds() -> [AppSound] {
        var discovered: [AppSound] = []
        let supportedExtensions = Set(["aiff", "aif", "caf", "wav", "mp3", "m4a"])

        var searchURLs: [URL] = []
        let sysSoundsDir = URL(fileURLWithPath: "/System/Library/Sounds")
        if FileManager.default.fileExists(atPath: sysSoundsDir.path) {
            searchURLs.append(sysSoundsDir)
        }
        if let systemLib = FileManager.default.urls(for: .libraryDirectory, in: .systemDomainMask).first {
            let sDir = systemLib.appendingPathComponent("Sounds", isDirectory: true)
            if !searchURLs.contains(sDir) { searchURLs.append(sDir) }
        }
        if let localLib = FileManager.default.urls(for: .libraryDirectory, in: .localDomainMask).first {
            let sDir = localLib.appendingPathComponent("Sounds", isDirectory: true)
            if !searchURLs.contains(sDir) { searchURLs.append(sDir) }
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

        // Fallback check: standard named system alert sounds via NSSound
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
            // Filter out SwiftCode's own installed sounds
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

    /// Complete unified library of all available sounds (Custom + System + User)
    public static var allSounds: [AppSound] {
        return customSounds + systemSounds + discoverUserSounds()
    }

    /// Retrieve a sound by its stable identifier with full backward compatibility
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

        // 4. Backward compatibility: match legacy IDs
        switch id {
        case "swiftcode_notification_a": return notificationA
        case "swiftcode_notification_b": return notificationB
        case "swiftcode_notification_c": return notificationC
        case "swiftcode_notification_d": return notificationD
        case "swiftcode_notification_e": return notificationE
        case "swiftcode_notification_f": return notificationF
        case "swiftcode_notification_g": return notificationG
        case "swiftcode_notification_h": return notificationH
        case "swiftcode_message_a":      return messageA
        case "swiftcode_message_b":      return messageB
        case "swiftcode_message_c":      return messageC
        case "swiftcode_message_d":      return messageD
        case "swiftcode_message_e":      return messageE
        case "swiftcode_success_a":      return successA
        case "swiftcode_success_b":      return successB
        case "swiftcode_success_c":      return successC
        case "swiftcode_success_d":      return successD
        case "swiftcode_error_a":        return errorA
        case "swiftcode_error_b":        return errorB
        case "swiftcode_error_c":        return errorC
        case "swiftcode_warning_a":      return warningA
        case "swiftcode_complete_a":     return completeA
        case "swiftcode_complete_b":     return completeB
        case "swiftcode_complete_c":     return completeC
        case "swiftcode_complete_d":     return completeD
        default:
            break
        }

        // 5. Match by exact filename or stripped ID
        for sound in allSounds {
            if sound.filename == id || sound.id.replacingOccurrences(of: "custom.", with: "") == id {
                return sound
            }
        }

        return nil
    }

    /// Retrieve custom sounds by category
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
                let matchesFile = sound.filename.localizedCaseInsensitiveContains(query)
                return matchesName || matchesCategory || matchesSource || matchesFile
            }
            return true
        }
    }

    /// Default sound for each event category
    public static func defaultSound(for category: AppSoundCategory) -> AppSound {
        switch category {
        case .chill:        return chillSoftBloom
        case .vibe:         return vibePulse
        case .satisfying:   return satisfyingPerfect
        case .success:      return successComplete
        case .complete:     return successComplete
        case .message:      return messageMessage
        case .notification: return notificationSoftNotify
        case .error:        return errorAttention
        }
    }
}
