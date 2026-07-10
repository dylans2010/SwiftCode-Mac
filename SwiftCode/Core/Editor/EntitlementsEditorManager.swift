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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
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
