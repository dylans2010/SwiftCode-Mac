import Foundation

import Foundation

public enum EntitlementPlatform: String, Codable, Sendable, CaseIterable {
    case macOS
    case iOS
    case tvOS
    case watchOS
    case visionOS
}

public enum EntitlementCategory: String, Codable, Sendable, CaseIterable {
    case sandbox = "App Sandbox"
    case network = "Network & Security"
    case hardware = "Hardware & Media"
    case storage = "Storage & Files"
    case system = "System Extensions & Drivers"
    case capabilities = "Apple Capabilities"
}

public enum EntitlementValueType: String, Codable, Sendable {
    case boolean = "Boolean"
    case string = "String"
    case array = "Array"
    case dictionary = "Dictionary"
}

public struct EntitlementDocumentation: Codable, Sendable {
    public let referenceURL: String
    public let description: String

    public init(referenceURL: String, description: String) {
        self.referenceURL = referenceURL
        self.description = description
    }
}

public struct EntitlementMetadata: Codable, Sendable, Identifiable {
    public var id: String { rawKey }
    public let displayName: String
    public let rawKey: String
    public let category: EntitlementCategory
    public let entitlementDescription: String
    public let supportedPlatforms: [EntitlementPlatform]
    public let minimumOS: String
    public let defaultValue: String
    public let valueType: EntitlementValueType
    public let validationRules: String
    public let searchKeywords: [String]
    public let recommendedUsage: String
    public let sfSymbol: String
    public let displayColorHex: String

    public init(
        displayName: String,
        rawKey: String,
        category: EntitlementCategory,
        entitlementDescription: String,
        supportedPlatforms: [EntitlementPlatform],
        minimumOS: String,
        defaultValue: String,
        valueType: EntitlementValueType,
        validationRules: String,
        searchKeywords: [String],
        recommendedUsage: String,
        sfSymbol: String,
        displayColorHex: String
    ) {
        self.displayName = displayName
        self.rawKey = rawKey
        self.category = category
        self.entitlementDescription = entitlementDescription
        self.supportedPlatforms = supportedPlatforms
        self.minimumOS = minimumOS
        self.defaultValue = defaultValue
        self.valueType = valueType
        self.validationRules = validationRules
        self.searchKeywords = searchKeywords
        self.recommendedUsage = recommendedUsage
        self.sfSymbol = sfSymbol
        self.displayColorHex = displayColorHex
    }
}

public struct Entitlement: Codable, Sendable, Identifiable {
    public var id: String { metadata.rawKey }
    public let metadata: EntitlementMetadata
    public var currentValue: String
    public var isEnabled: Bool

    public init(metadata: EntitlementMetadata, currentValue: String, isEnabled: Bool = false) {
        self.metadata = metadata
        self.currentValue = currentValue
        self.isEnabled = isEnabled
    }
}

public struct EntitlementValidationResult: Codable, Sendable {
    public let isValid: Bool
    public let warnings: [EntitlementWarning]
    public let errors: [EntitlementError]

    public init(isValid: Bool, warnings: [EntitlementWarning], errors: [EntitlementError]) {
        self.isValid = isValid
        self.warnings = warnings
        self.errors = errors
    }
}

public struct EntitlementWarning: Codable, Sendable, Identifiable {
    public var id: String { message }
    public let rawKey: String
    public let message: String

    public init(rawKey: String, message: String) {
        self.rawKey = rawKey
        self.message = message
    }
}

public struct EntitlementError: Codable, Sendable, Identifiable {
    public var id: String { message }
    public let rawKey: String
    public let message: String

    public init(rawKey: String, message: String) {
        self.rawKey = rawKey
        self.message = message
    }
}

public struct EntitlementGroup: Codable, Sendable {}
public struct EntitlementSection: Codable, Sendable {}
public struct EntitlementCapability: Codable, Sendable {}
public struct EntitlementAvailability: Codable, Sendable {}

public struct EntitlementsCatalog {
    public static let all: [EntitlementMetadata] = [
        EntitlementMetadata(
            displayName: "App Sandbox",
            rawKey: "com.apple.security.app-sandbox",
            category: .sandbox,
            entitlementDescription: "Restricts access to system resources and user data to protect against compromised apps.",
            supportedPlatforms: [.macOS],
            minimumOS: "10.7",
            defaultValue: "true",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["sandbox", "security", "jail", "protect"],
            recommendedUsage: "Mandatory for Mac App Store distribution.",
            sfSymbol: "lock.shield.fill",
            displayColorHex: "#007AFF"
        ),
        EntitlementMetadata(
            displayName: "Network Client (Outgoing)",
            rawKey: "com.apple.security.network.client",
            category: .network,
            entitlementDescription: "Allows the app to establish outgoing network connections to network servers.",
            supportedPlatforms: [.macOS],
            minimumOS: "10.7",
            defaultValue: "true",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["network", "client", "outgoing", "internet"],
            recommendedUsage: "Required if your app fetches data from remote servers.",
            sfSymbol: "arrow.up.right.circle.fill",
            displayColorHex: "#34C759"
        ),
        EntitlementMetadata(
            displayName: "Network Server (Incoming)",
            rawKey: "com.apple.security.network.server",
            category: .network,
            entitlementDescription: "Allows the app to listen for incoming network connections and host network services.",
            supportedPlatforms: [.macOS],
            minimumOS: "10.7",
            defaultValue: "false",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["network", "server", "incoming", "host"],
            recommendedUsage: "Required for web servers, peer-to-peer sharing, or local multiplayer hosting.",
            sfSymbol: "arrow.down.left.circle.fill",
            displayColorHex: "#FF9500"
        ),
        EntitlementMetadata(
            displayName: "Camera Access",
            rawKey: "com.apple.security.device.camera",
            category: .hardware,
            entitlementDescription: "Allows the app to record or capture frames using the system cameras.",
            supportedPlatforms: [.macOS],
            minimumOS: "10.7",
            defaultValue: "false",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["camera", "hardware", "video", "capture"],
            recommendedUsage: "Enable if building an image scanner, video recorder, or avatar editor.",
            sfSymbol: "camera.fill",
            displayColorHex: "#FF2D55"
        ),
        EntitlementMetadata(
            displayName: "Microphone Access",
            rawKey: "com.apple.security.device.audio-input",
            category: .hardware,
            entitlementDescription: "Allows the app to record sound waves using the system microphones.",
            supportedPlatforms: [.macOS],
            minimumOS: "10.7",
            defaultValue: "false",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["microphone", "audio", "mic", "sound"],
            recommendedUsage: "Required for recording voice notes or voice calling integrations.",
            sfSymbol: "mic.fill",
            displayColorHex: "#AF52DE"
        ),
        EntitlementMetadata(
            displayName: "User Downloads Folder (Read/Write)",
            rawKey: "com.apple.security.assets.downloads.read-write",
            category: .storage,
            entitlementDescription: "Grants read and write access to files in the user's Downloads folder.",
            supportedPlatforms: [.macOS],
            minimumOS: "10.7",
            defaultValue: "false",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["downloads", "files", "folder", "storage"],
            recommendedUsage: "Required if your app downloads documents and saves them to user downloads.",
            sfSymbol: "arrow.down.doc.fill",
            displayColorHex: "#5AC8FA"
        ),
        EntitlementMetadata(
            displayName: "Hardware USB Access",
            rawKey: "com.apple.security.device.usb",
            category: .hardware,
            entitlementDescription: "Allows the app to communicate directly with connected USB devices.",
            supportedPlatforms: [.macOS],
            minimumOS: "10.7",
            defaultValue: "false",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["usb", "hardware", "external", "accessory"],
            recommendedUsage: "Enable if implementing low-level firmware flashing or custom hardware connectivity.",
            sfSymbol: "usb",
            displayColorHex: "#8E8E93"
        ),
        EntitlementMetadata(
            displayName: "App Groups",
            rawKey: "com.apple.security.application-groups",
            category: .capabilities,
            entitlementDescription: "Enables sharing data and user preferences between multiple apps or extensions.",
            supportedPlatforms: [.macOS, .iOS, .watchOS, .tvOS],
            minimumOS: "10.10",
            defaultValue: "[]",
            valueType: .array,
            validationRules: "Must be an array of group identifiers.",
            searchKeywords: ["groups", "app groups", "share", "extension"],
            recommendedUsage: "Enable if building watch extensions, widget extensions, or companion utilities.",
            sfSymbol: "square.3.layers.3d",
            displayColorHex: "#5856D6"
        ),
        EntitlementMetadata(
            displayName: "Keychain Sharing",
            rawKey: "keychain-access-groups",
            category: .capabilities,
            entitlementDescription: "Allows securely sharing passwords and secure tokens in the iOS/macOS Keychain across sibling apps.",
            supportedPlatforms: [.macOS, .iOS, .watchOS, .tvOS],
            minimumOS: "10.9",
            defaultValue: "[]",
            valueType: .array,
            validationRules: "Must be an array of keychain group IDs",
            searchKeywords: ["keychain", "security", "passwords", "tokens"],
            recommendedUsage: "Required to share credentials silently without asking the user to sign in twice.",
            sfSymbol: "key.fill",
            displayColorHex: "#FFCC00"
        ),
        EntitlementMetadata(
            displayName: "Push Notifications",
            rawKey: "aps-environment",
            category: .capabilities,
            entitlementDescription: "Registers the app for Apple Push Notification service (APNs).",
            supportedPlatforms: [.macOS, .iOS, .watchOS, .tvOS, .visionOS],
            minimumOS: "10.7",
            defaultValue: "development",
            valueType: .string,
            validationRules: "Must be 'development' or 'production'",
            searchKeywords: ["push", "apns", "notifications", "alerts"],
            recommendedUsage: "Required to deliver remote push notifications to devices.",
            sfSymbol: "bell.badge.fill",
            displayColorHex: "#FF3B30"
        ),
        EntitlementMetadata(
            displayName: "Sign in with Apple",
            rawKey: "com.apple.developer.applesignin",
            category: .capabilities,
            entitlementDescription: "Allows users to sign into your app securely using their Apple ID.",
            supportedPlatforms: [.macOS, .iOS, .watchOS, .tvOS, .visionOS],
            minimumOS: "10.15",
            defaultValue: "[\"Default\"]",
            valueType: .array,
            validationRules: "Must be an array containing 'Default'",
            searchKeywords: ["apple sign in", "auth", "login", "identity"],
            recommendedUsage: "Required if your app provides third-party social logins.",
            sfSymbol: "apple.logo",
            displayColorHex: "#000000"
        ),
        EntitlementMetadata(
            displayName: "Associated Domains",
            rawKey: "com.apple.developer.associated-domains",
            category: .network,
            entitlementDescription: "Associates your app with specific domains for Universal Links and Shared Web Credentials.",
            supportedPlatforms: [.macOS, .iOS, .watchOS, .visionOS],
            minimumOS: "10.15",
            defaultValue: "[]",
            valueType: .array,
            validationRules: "Array of domain strings prefixed with applinks:, webcredentials:, etc.",
            searchKeywords: ["domains", "universal links", "credentials", "handoff"],
            recommendedUsage: "Required for universal deep links opening inside the application.",
            sfSymbol: "link",
            displayColorHex: "#007AFF"
        ),
        EntitlementMetadata(
            displayName: "Live Activities Updates",
            rawKey: "com.apple.developer.live-activities",
            category: .capabilities,
            entitlementDescription: "Allows pushing real-time dynamic ActivityKit updates to the Dynamic Island and Lock Screen.",
            supportedPlatforms: [.iOS, .visionOS],
            minimumOS: "16.1",
            defaultValue: "true",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["live activities", "dynamic island", "lock screen", "activitykit"],
            recommendedUsage: "Required for frequent push notifications updating Live Activities.",
            sfSymbol: "waveform.path.badge.plus",
            displayColorHex: "#FF9500"
        ),
        EntitlementMetadata(
            displayName: "WeatherKit",
            rawKey: "com.apple.developer.weatherkit",
            category: .capabilities,
            entitlementDescription: "Enables Apple WeatherKit framework access for high-resolution global weather forecasts.",
            supportedPlatforms: [.macOS, .iOS, .watchOS, .tvOS, .visionOS],
            minimumOS: "16.0",
            defaultValue: "true",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["weather", "forecast", "weatherkit", "climate"],
            recommendedUsage: "Required when consuming Apple Weather service APIs.",
            sfSymbol: "cloud.sun.rain.fill",
            displayColorHex: "#007AFF"
        ),
        EntitlementMetadata(
            displayName: "Virtualization Framework",
            rawKey: "com.apple.developer.virtualization",
            category: .capabilities,
            entitlementDescription: "Allows the app to create, configure, and boot virtual machines on macOS.",
            supportedPlatforms: [.macOS],
            minimumOS: "11.0",
            defaultValue: "true",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["virtualization", "vm", "virtual machine", "hypervisor"],
            recommendedUsage: "Required to launch Linux and macOS virtual machines via Virtualization.framework.",
            sfSymbol: "desktopcomputer.trianglebadge.exclamationmark",
            displayColorHex: "#5856D6"
        ),
        EntitlementMetadata(
            displayName: "Tap to Pay on iPhone",
            rawKey: "com.apple.developer.proximity-reader.payment.acceptance",
            category: .capabilities,
            entitlementDescription: "Enables contactless in-person payment acceptance using ProximityReader on supported iPhones.",
            supportedPlatforms: [.iOS],
            minimumOS: "15.4",
            defaultValue: "true",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["tap to pay", "contactless", "payment", "proximity"],
            recommendedUsage: "Required for accepting EMV contactless credit and debit cards.",
            sfSymbol: "wave.3.forward.circle.fill",
            displayColorHex: "#34C759"
        ),
        EntitlementMetadata(
            displayName: "DockKit Accessory Tracking",
            rawKey: "com.apple.developer.dock-accessory",
            category: .hardware,
            entitlementDescription: "Allows motorized tracking stands and docks to track subjects automatically via DockKit.",
            supportedPlatforms: [.iOS],
            minimumOS: "17.0",
            defaultValue: "true",
            valueType: .boolean,
            validationRules: "Must be boolean",
            searchKeywords: ["dockkit", "dock", "tracking", "motorized", "stand"],
            recommendedUsage: "Required for subject tracking with DockKit motorized hardware.",
            sfSymbol: "video.badge.waveform",
            displayColorHex: "#FF9500"
        )
    ]
}
