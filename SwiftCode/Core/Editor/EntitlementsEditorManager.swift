import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Core", category: "EntitlementsEditorManager")

// MARK: - Models

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

public struct EntitlementChange: Codable, Sendable, Identifiable {
    public var id: UUID
    public let rawKey: String
    public let oldValue: String
    public let newValue: String
    public let timestamp: Date

    public init(rawKey: String, oldValue: String, newValue: String) {
        self.id = UUID()
        self.rawKey = rawKey
        self.oldValue = oldValue
        self.newValue = newValue
        self.timestamp = Date()
    }
}

// Dummy conformance stubs as requested by structural modeling:
public struct EntitlementGroup: Codable, Sendable {}
public struct EntitlementSection: Codable, Sendable {}
public struct EntitlementCapability: Codable, Sendable {}
public struct EntitlementAvailability: Codable, Sendable {}

// MARK: - Entitlements Catalog

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
        )
    ]
}

// MARK: - EntitlementsEditorManager

public final class EntitlementsEditorManager: Sendable {
    public let fileURL: URL

    // Non-isolated / concurrency isolated states handled by Thread-safe mechanisms or MainActor UI
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Read entitlements dictionary from disk.
    public func readEntitlements() throws -> [String: Any] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            logger.info("Entitlements file not found at \(self.fileURL.path). Returning empty template.")
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        if let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return plist
        }
        return [:]
    }

    /// Write active entitlements dictionary back to disk.
    public func writeEntitlements(_ entitlements: [String: Any]) throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            throw NSError(domain: "EntitlementsEditorManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "The target path is a directory, not an entitlements file: \(fileURL.lastPathComponent)"])
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sorted = sortDictionary(entitlements)
        let data = try PropertyListSerialization.data(fromPropertyList: sorted, format: .xml, options: 0)
        try data.write(to: fileURL, options: .atomic)
        logger.info("Successfully wrote entitlements plist at \(self.fileURL.path).")
    }

    private func sortDictionary(_ dict: [String: Any]) -> [String: Any] {
        var sorted: [String: Any] = [:]
        for key in dict.keys.sorted() {
            if let valDict = dict[key] as? [String: Any] {
                sorted[key] = sortDictionary(valDict)
            } else if let valArray = dict[key] as? [[String: Any]] {
                sorted[key] = valArray.map { sortDictionary($0) }
            } else {
                sorted[key] = dict[key]
            }
        }
        return sorted
    }

    /// Run deep structural validation on entitlements.
    public func validate(_ entitlements: [String: Any]) -> EntitlementValidationResult {
        var warnings: [EntitlementWarning] = []
        var errors: [EntitlementError] = []

        // 1. Sandbox verification
        if let sandboxVal = entitlements["com.apple.security.app-sandbox"] as? Bool {
            if !sandboxVal {
                warnings.append(EntitlementWarning(
                    rawKey: "com.apple.security.app-sandbox",
                    message: "App Sandbox is disabled. This will prevent App Store distribution."
                ))
            }
        } else {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.app-sandbox",
                message: "App Sandbox entitlement is missing entirely."
            ))
        }

        // 2. Outgoing network without sandbox warning
        let hasNetwork = entitlements["com.apple.security.network.client"] as? Bool ?? false
        let hasSandbox = entitlements["com.apple.security.app-sandbox"] as? Bool ?? false
        if hasNetwork && !hasSandbox {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.network.client",
                message: "Network Client outgoing connections are enabled, but App Sandbox is inactive."
            ))
        }

        // 3. App group format check
        if let groups = entitlements["com.apple.security.application-groups"] {
            if !(groups is [String]) {
                errors.append(EntitlementError(
                    rawKey: "com.apple.security.application-groups",
                    message: "App Groups entitlement must be an array of strings."
                ))
            }
        }

        let isValid = errors.isEmpty
        return EntitlementValidationResult(isValid: isValid, warnings: warnings, errors: errors)
    }

    /// Cross-entitlement consistency checks beyond the base validate(_:).
    /// Kept as a separate function so the base validation contract is unchanged.
    /// Pure function: inspects the dictionary, performs no I/O.
    public func crossEntitlementIssues(_ entitlements: [String: Any]) -> EntitlementValidationResult {
        var warnings: [EntitlementWarning] = []
        var errors: [EntitlementError] = []

        let sandbox = entitlements["com.apple.security.app-sandbox"] as? Bool ?? false

        // aps-environment must be one of the two real values.
        if let aps = entitlements["aps-environment"] {
            if let value = aps as? String, value == "development" || value == "production" {
                // valid
            } else {
                errors.append(EntitlementError(
                    rawKey: "aps-environment",
                    message: "aps-environment must be \"development\" or \"production\"."
                ))
            }
        }

        // Sandbox resource entitlements have no effect without the sandbox master switch.
        if !sandbox {
            for key in ["com.apple.security.network.client", "com.apple.security.network.server"] {
                if entitlements[key] != nil {
                    warnings.append(EntitlementWarning(
                        rawKey: key,
                        message: "This entitlement is set but App Sandbox is off; sandbox resource entitlements have no effect without it."
                    ))
                }
            }
        }

        // Hardware / personal-information keys only apply to sandboxed apps on macOS.
        for key in [
            "com.apple.security.device.camera",
            "com.apple.security.device.audio-input",
            "com.apple.security.personal-information.photos-library",
            "com.apple.security.personal-information.location"
        ] where entitlements[key] != nil && !sandbox {
            warnings.append(EntitlementWarning(
                rawKey: key,
                message: "This entitlement only takes effect in a sandboxed app, but App Sandbox is off."
            ))
        }

        // Redundant read-only + read-write pairs for the same folder.
        let folderPairs = [
            ("com.apple.security.files.user-selected.read-only", "com.apple.security.files.user-selected.read-write"),
            ("com.apple.security.assets.downloads.read-only", "com.apple.security.assets.downloads.read-write"),
            ("com.apple.security.assets.pictures.read-only", "com.apple.security.assets.pictures.read-write"),
            ("com.apple.security.assets.music.read-only", "com.apple.security.assets.music.read-write"),
            ("com.apple.security.assets.movies.read-only", "com.apple.security.assets.movies.read-write")
        ]
        for (readOnly, readWrite) in folderPairs
            where entitlements[readOnly] != nil && entitlements[readWrite] != nil {
            warnings.append(EntitlementWarning(
                rawKey: readOnly,
                message: "Read-write access already includes read access; the read-only key for this folder is redundant."
            ))
        }

        // Hardened Runtime keys only matter for Developer ID / notarized distribution.
        let csKeys = [
            "com.apple.security.cs.allow-jit",
            "com.apple.security.cs.allow-unsigned-executable-memory",
            "com.apple.security.cs.disable-library-validation",
            "com.apple.security.cs.allow-dyld-environment-variables",
            "com.apple.security.cs.debugger"
        ]
        if sandbox, csKeys.contains(where: { entitlements[$0] != nil }) {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.cs.*",
                message: "Hardened Runtime entitlements apply to Developer ID / notarized distribution; Mac App Store builds enforce their own runtime policy."
            ))
        }

        // iCloud consistency.
        let containers = entitlements["com.apple.developer.icloud-container-identifiers"]
        let services = entitlements["com.apple.developer.icloud-services"] as? [String]
        if containers != nil && (services?.isEmpty ?? true) {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.developer.icloud-container-identifiers",
                message: "iCloud container identifiers are set but no iCloud services (CloudDocuments / CloudKit) are enabled."
            ))
        }
        if let services, !services.isEmpty, containers == nil {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.developer.icloud-services",
                message: "iCloud services are enabled but no container identifiers are set."
            ))
        }
        if entitlements["NSUbiquitousContainers"] != nil && containers == nil {
            warnings.append(EntitlementWarning(
                rawKey: "NSUbiquitousContainers",
                message: "Ubiquitous containers are declared but no iCloud container identifiers are set."
            ))
        }

        // App Groups format.
        if let groups = entitlements["com.apple.security.application-groups"] {
            if let arr = groups as? [String] {
                if arr.isEmpty {
                    warnings.append(EntitlementWarning(
                        rawKey: "com.apple.security.application-groups",
                        message: "App Groups is enabled with an empty identifier list."
                    ))
                } else if arr.contains(where: { !$0.hasPrefix("group.") }) {
                    warnings.append(EntitlementWarning(
                        rawKey: "com.apple.security.application-groups",
                        message: "App Group identifiers should begin with \"group.\"."
                    ))
                }
            } else {
                errors.append(EntitlementError(
                    rawKey: "com.apple.security.application-groups",
                    message: "App Groups must be an array of strings."
                ))
            }
        }

        // Keychain access groups format.
        if let keychain = entitlements["keychain-access-groups"] {
            if let arr = keychain as? [String] {
                if arr.isEmpty {
                    warnings.append(EntitlementWarning(
                        rawKey: "keychain-access-groups",
                        message: "Keychain Access Groups is enabled with an empty identifier list."
                    ))
                }
            } else {
                errors.append(EntitlementError(
                    rawKey: "keychain-access-groups",
                    message: "Keychain Access Groups must be an array of strings."
                ))
            }
        }

        // Associated Domains prefixes.
        let knownPrefixes = ["applinks:", "webcredentials:", "activitycontinuation:", "appclips:"]
        if let domains = entitlements["com.apple.developer.associated-domains"] as? [String] {
            let bad = domains.filter { domain in !knownPrefixes.contains(where: domain.hasPrefix) }
            if !bad.isEmpty {
                warnings.append(EntitlementWarning(
                    rawKey: "com.apple.developer.associated-domains",
                    message: "Entries should begin with one of applinks:, webcredentials:, activitycontinuation:, appclips:."
                ))
            }
        }

        // Default data protection value.
        let validDDP = [
            "NSFileProtectionComplete",
            "NSFileProtectionCompleteUnlessOpen",
            "NSFileProtectionCompleteUntilFirstUserAuthentication",
            "NSFileProtectionNone"
        ]
        if let ddp = entitlements["com.apple.developer.default-data-protection"] as? String,
           !validDDP.contains(ddp) {
            errors.append(EntitlementError(
                rawKey: "com.apple.developer.default-data-protection",
                message: "Unknown data protection class. Use one of the NSFileProtection values."
            ))
        }

        // Incoming connections draw extra review scrutiny — honest heads-up, not an error.
        if entitlements["com.apple.security.network.server"] as? Bool == true {
            warnings.append(EntitlementWarning(
                rawKey: "com.apple.security.network.server",
                message: "Incoming network connections may draw extra App Review scrutiny; be ready to explain why the app listens."
            ))
        }

        // Special-approval entitlements: the key alone does not grant access.
        for key in [
            "com.apple.developer.driverkit",
            "com.apple.developer.endpoint-security.client",
            "com.apple.developer.networking.networkextension",
            "com.apple.developer.system-extension.install"
        ] where entitlements[key] != nil {
            warnings.append(EntitlementWarning(
                rawKey: key,
                message: "Requires a special entitlement request to Apple — the key alone does not grant access."
            ))
        }

        return EntitlementValidationResult(isValid: errors.isEmpty, warnings: warnings, errors: errors)
    }

    /// Generates raw XML content for previewing or debugging.
    public func generateRawXML(_ entitlements: [String: Any]) -> String {
        let sorted = sortDictionary(entitlements)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: sorted, format: .xml, options: 0),
              let xmlString = String(data: data, encoding: .utf8) else {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n</dict>\n</plist>"
        }
        return xmlString
    }

    /// Parse raw XML text back to structured dictionary.
    public func parseRawXML(_ xml: String) throws -> [String: Any] {
        guard let data = xml.data(using: .utf8) else {
            throw NSError(domain: "EntitlementsEditorManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 encoding"])
        }
        if let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            return dict
        }
        throw NSError(domain: "EntitlementsEditorManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "XML plist is not a valid dictionary."])
    }
}
