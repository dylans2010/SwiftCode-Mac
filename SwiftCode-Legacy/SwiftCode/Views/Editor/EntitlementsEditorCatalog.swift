import Foundation

// MARK: - Capability Sections

/// Capability sections shown as filter categories and UI groups.
public enum EntitlementCapabilitySection: String, CaseIterable, Identifiable {
    case all = "All"
    case sandbox = "Sandbox"
    case hardenedRuntime = "Hardened"
    case cloud = "Cloud"
    case sharing = "Sharing"
    case personal = "Personal"
    case services = "Services"
    case systemExtensions = "Extensions"
    case other = "Other"

    public var id: String { rawValue }

    public var fullTitle: String {
        switch self {
        case .all: return "All Capabilities"
        case .sandbox: return "App Sandbox"
        case .hardenedRuntime: return "Hardened Runtime"
        case .cloud: return "iCloud & Push"
        case .sharing: return "Sharing"
        case .personal: return "Personal Information"
        case .services: return "Apple Services"
        case .systemExtensions: return "System & Driver Extensions"
        case .other: return "Other Keys"
        }
    }

    public var icon: String {
        switch self {
        case .all: return "lock.shield"
        case .sandbox: return "cube.transparent"
        case .hardenedRuntime: return "hammer"
        case .cloud: return "icloud"
        case .sharing: return "square.stack.3d"
        case .personal: return "person.crop.circle"
        case .services: return "app.badge"
        case .systemExtensions: return "cpu"
        case .other: return "key"
        }
    }
}

/// What kind of payload a capability carries beyond its on/off switch.
public enum CapabilityPayloadKind {
    /// Pure boolean toggle — enabling sets the key, disabling removes it.
    case none
    /// An array of string identifiers the user can add/remove.
    case idList(placeholder: String)
    /// An array of strings restricted to a fixed set of real values.
    case fixedValueList(allowed: [String])
    /// A string picked from a fixed set of options.
    case choice(options: [String])
    /// A free-form string value.
    case stringValue(placeholder: String)
    /// An array of strings built from a service prefix plus a host (Associated Domains).
    case prefixedList(prefixes: [String], placeholder: String)
    /// iCloud composite: container identifiers + key-value store identifier + NSUbiquitousContainers.
    case iCloudComposite
}

/// One toggleable capability. Enabling it writes the real entitlement key;
/// disabling it removes the key from the entitlements file.
public struct CapabilityDefinition: Identifiable {
    public var id: String { rawKey }
    public let rawKey: String
    public let name: String
    public let explanation: String
    public let symbol: String
    public let section: EntitlementCapabilitySection
    public let payload: CapabilityPayloadKind
    public let defaultValue: Any
    /// Composite capabilities control more than one entitlement key (e.g. iCloud).
    public let compositeKeys: [String]
    /// True when Apple only grants the entitlement through a special request.
    public let requiresSpecialApproval: Bool

    public init(
        rawKey: String,
        name: String,
        explanation: String,
        symbol: String,
        section: EntitlementCapabilitySection,
        payload: CapabilityPayloadKind,
        defaultValue: Any,
        compositeKeys: [String] = [],
        requiresSpecialApproval: Bool = false
    ) {
        self.rawKey = rawKey
        self.name = name
        self.explanation = explanation
        self.symbol = symbol
        self.section = section
        self.payload = payload
        self.defaultValue = defaultValue
        self.compositeKeys = compositeKeys
        self.requiresSpecialApproval = requiresSpecialApproval
    }
}

public enum CapabilityCatalog {
    public static let iCloudContainersKey = "com.apple.developer.icloud-container-identifiers"
    public static let iCloudServicesKey = "com.apple.developer.icloud-services"
    public static let iCloudKVStoreKey = "com.apple.developer.ubiquity-kvstore-identifier"
    public static let ubiquitousContainersKey = "NSUbiquitousContainers"

    nonisolated(unsafe) public static let definitions: [CapabilityDefinition] = [
        // MARK: App Sandbox
        CapabilityDefinition(
            rawKey: "com.apple.security.app-sandbox",
            name: "App Sandbox",
            explanation: "Master switch. Restricts the app to only the system resources it explicitly requests. Required for Mac App Store distribution.",
            symbol: "lock.shield.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.network.client",
            name: "Outgoing Connections",
            explanation: "Allows the app to make outgoing network connections, e.g. calling web APIs or downloading content.",
            symbol: "arrow.up.right.circle",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.network.server",
            name: "Incoming Connections",
            explanation: "Allows the app to listen for incoming network connections and host local services.",
            symbol: "arrow.down.left.circle",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.user-selected.read-only",
            name: "User-Selected Files (Read)",
            explanation: "Lets the app read files the user explicitly opens through Open panels or drag and drop.",
            symbol: "folder",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.user-selected.read-write",
            name: "User-Selected Files (Read & Write)",
            explanation: "Lets the app read and write files the user explicitly opens through Open and Save panels or drag and drop.",
            symbol: "folder.badge.plus",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.downloads.read-only",
            name: "Downloads Folder (Read)",
            explanation: "Grants read access to files inside the user's Downloads folder without prompting.",
            symbol: "arrow.down.doc",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.downloads.read-write",
            name: "Downloads Folder (Read & Write)",
            explanation: "Grants read and write access to files inside the user's Downloads folder without prompting.",
            symbol: "arrow.down.doc.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.pictures.read-only",
            name: "Pictures Folder (Read)",
            explanation: "Grants read access to the user's Pictures folder, commonly used for image pickers.",
            symbol: "photo",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.pictures.read-write",
            name: "Pictures Folder (Read & Write)",
            explanation: "Grants read and write access to the user's Pictures folder, for apps that save images.",
            symbol: "photo.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.music.read-only",
            name: "Music Folder (Read)",
            explanation: "Grants read access to the user's Music folder for media library features.",
            symbol: "music.note",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.music.read-write",
            name: "Music Folder (Read & Write)",
            explanation: "Grants read and write access to the user's Music folder for media library features.",
            symbol: "music.note.list",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.movies.read-only",
            name: "Movies Folder (Read)",
            explanation: "Grants read access to the user's Movies folder for media library features.",
            symbol: "film",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.assets.movies.read-write",
            name: "Movies Folder (Read & Write)",
            explanation: "Grants read and write access to the user's Movies folder for media library features.",
            symbol: "film.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.print",
            name: "Printing",
            explanation: "Allows the app to print documents while sandboxed.",
            symbol: "printer.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.usb",
            name: "USB Devices",
            explanation: "Allows the app to communicate directly with connected USB accessories and hardware.",
            symbol: "cable.connector",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.audio-input",
            name: "Microphone",
            explanation: "Allows the app to record audio using the system microphones. Pair with an NSMicrophoneUsageDescription key in Info.plist.",
            symbol: "mic.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.camera",
            name: "Camera",
            explanation: "Allows the app to capture photos and video using the system cameras. Pair with an NSCameraUsageDescription key in Info.plist.",
            symbol: "camera.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.bluetooth",
            name: "Bluetooth",
            explanation: "Allows the app to communicate with Bluetooth accessories while sandboxed.",
            symbol: "bluetooth",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),

        // MARK: Hardened Runtime
        CapabilityDefinition(
            rawKey: "com.apple.security.cs.allow-jit",
            name: "Allow JIT Code Generation",
            explanation: "Lets the app generate machine code at runtime and execute it. Required by JavaScript engines and emulators; weakens code-signing protection.",
            symbol: "memorychip",
            section: .hardenedRuntime,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.cs.allow-unsigned-executable-memory",
            name: "Allow Unsigned Executable Memory",
            explanation: "Lets the app map memory that is both writable and executable without a valid code signature. Needed by some JIT engines.",
            symbol: "memorychip.fill",
            section: .hardenedRuntime,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.cs.disable-library-validation",
            name: "Disable Library Validation",
            explanation: "Lets the app load plug-ins, frameworks, and libraries signed by a different Team ID. Required for apps with third-party plug-ins.",
            symbol: "puzzlepiece",
            section: .hardenedRuntime,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.cs.allow-dyld-environment-variables",
            name: "Allow DYLD Environment Variables",
            explanation: "Lets DYLD_ environment variables and library interposing affect the app at launch. Handy for debugging; leave off in shipping builds.",
            symbol: "terminal",
            section: .hardenedRuntime,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.cs.debugger",
            name: "Allow Debugger Attachment",
            explanation: "Lets another process attach with task_for_pid so a debugger can control the app. Needed to debug Developer ID builds outside Xcode.",
            symbol: "ladybug",
            section: .hardenedRuntime,
            payload: .none,
            defaultValue: true
        ),

        // MARK: iCloud & Push
        CapabilityDefinition(
            rawKey: iCloudContainersKey,
            name: "iCloud",
            explanation: "Syncs documents and key-value data through the user's iCloud account. Configure the container identifiers, the key-value store identifier, and any ubiquitous containers below.",
            symbol: "icloud.fill",
            section: .cloud,
            payload: .iCloudComposite,
            defaultValue: [String](),
            compositeKeys: [iCloudKVStoreKey, ubiquitousContainersKey]
        ),
        CapabilityDefinition(
            rawKey: iCloudServicesKey,
            name: "iCloud Services",
            explanation: "Which iCloud services the app uses. CloudDocuments syncs documents; CloudKit syncs structured records.",
            symbol: "cloud",
            section: .cloud,
            payload: .fixedValueList(allowed: ["CloudDocuments", "CloudKit"]),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "aps-environment",
            name: "Push Notifications",
            explanation: "Registers the app for Apple Push Notification service. Choose the environment that matches your provisioning profile; Xcode normally finalizes this at archive time.",
            symbol: "bell.badge",
            section: .cloud,
            payload: .choice(options: ["development", "production"]),
            defaultValue: "development"
        ),

        // MARK: Sharing
        CapabilityDefinition(
            rawKey: "com.apple.security.application-groups",
            name: "App Groups",
            explanation: "Lets the app share files and preferences with its extensions or companion apps through a shared container.",
            symbol: "square.stack.3d",
            section: .sharing,
            payload: .idList(placeholder: "group.com.example.app"),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "keychain-access-groups",
            name: "Keychain Access Groups",
            explanation: "Lets the app share passwords and tokens in the Keychain with sibling apps using the same access group.",
            symbol: "key.fill",
            section: .sharing,
            payload: .idList(placeholder: "$(AppIdentifierPrefix)com.example.app"),
            defaultValue: [String]()
        ),

        // MARK: Personal Information
        CapabilityDefinition(
            rawKey: "com.apple.security.personal-information.photos-library",
            name: "Photos Library",
            explanation: "Allows the app to access the user's Photos library. Pair with an NSPhotoLibraryUsageDescription key in Info.plist.",
            symbol: "photo.on.rectangle",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.personal-information.addressbook",
            name: "Contacts",
            explanation: "Allows the app to access the user's contacts. Pair with an NSContactsUsageDescription key in Info.plist.",
            symbol: "book.closed",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.personal-information.location",
            name: "Location",
            explanation: "Allows the app to access the user's location. Pair with an NSLocationWhenInUseUsageDescription key in Info.plist.",
            symbol: "location.fill",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.personal-information.calendars",
            name: "Calendars",
            explanation: "Allows the app to access the user's calendars. Pair with an NSCalendarsUsageDescription key in Info.plist.",
            symbol: "calendar",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),

        // MARK: Apple Services
        CapabilityDefinition(
            rawKey: "com.apple.developer.applesignin",
            name: "Sign in with Apple",
            explanation: "Lets users sign in with their Apple ID. The entitlement value is the array [\"Default\"].",
            symbol: "apple.logo",
            section: .services,
            payload: .fixedValueList(allowed: ["Default"]),
            defaultValue: ["Default"]
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.game-center",
            name: "Game Center",
            explanation: "Enables Game Center leaderboards, achievements, and multiplayer matchmaking.",
            symbol: "gamecontroller.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.maps",
            name: "Maps",
            explanation: "Grants access to Maps services. List the map identifiers your app is permitted to use.",
            symbol: "map.fill",
            section: .services,
            payload: .idList(placeholder: "com.example.maps"),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.siri",
            name: "Siri",
            explanation: "Lets the app donate Siri shortcuts and integrate with SiriKit intents.",
            symbol: "waveform",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.pass-type-identifiers",
            name: "Wallet Passes",
            explanation: "Pass Type identifiers the app can create and read in Wallet.",
            symbol: "wallet.pass.fill",
            section: .services,
            payload: .idList(placeholder: "pass.com.example.type"),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.homekit",
            name: "HomeKit",
            explanation: "Lets the app discover and communicate with HomeKit accessories in the user's home.",
            symbol: "house.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.healthkit",
            name: "HealthKit",
            explanation: "Lets the app read and write HealthKit data. Pair with NSHealthShareUsageDescription and NSHealthUpdateUsageDescription keys in Info.plist.",
            symbol: "heart.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.in-app-payments",
            name: "Apple Pay",
            explanation: "Merchant identifiers the app uses to accept Apple Pay payments.",
            symbol: "creditcard.fill",
            section: .services,
            payload: .idList(placeholder: "merchant.com.example.app"),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.associated-domains",
            name: "Associated Domains",
            explanation: "Domains associated with the app for universal links, shared web credentials, Handoff, and App Clips.",
            symbol: "link",
            section: .services,
            payload: .prefixedList(
                prefixes: ["applinks:", "webcredentials:", "activitycontinuation:", "appclips:"],
                placeholder: "example.com"
            ),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.default-data-protection",
            name: "Default Data Protection",
            explanation: "The file-protection class applied to new files the app creates.",
            symbol: "lock.fill",
            section: .services,
            payload: .choice(options: [
                "NSFileProtectionComplete",
                "NSFileProtectionCompleteUnlessOpen",
                "NSFileProtectionCompleteUntilFirstUserAuthentication",
                "NSFileProtectionNone"
            ]),
            defaultValue: "NSFileProtectionCompleteUntilFirstUserAuthentication"
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.devicecheck.appattest-environment",
            name: "App Attest Environment",
            explanation: "The server environment that App Attest assertions are validated against.",
            symbol: "checkmark.shield.fill",
            section: .services,
            payload: .choice(options: ["development", "production"]),
            defaultValue: "development"
        ),

        // MARK: System & Driver Extensions (special Apple approval required)
        CapabilityDefinition(
            rawKey: "com.apple.developer.driverkit",
            name: "DriverKit",
            explanation: "Lets the app's DriverKit extensions (dexts) drive hardware from user space.",
            symbol: "memorychip",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.endpoint-security.client",
            name: "Endpoint Security",
            explanation: "Lets the app receive Endpoint Security events describing process, file, and network activity.",
            symbol: "shield.fill",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.networking.networkextension",
            name: "Network Extensions",
            explanation: "Which Network Extension provider types the app's extensions implement.",
            symbol: "network",
            section: .systemExtensions,
            payload: .fixedValueList(allowed: [
                "app-proxy-provider",
                "content-filter-provider",
                "dns-proxy",
                "packet-tunnel-provider",
                "app-push-provider"
            ]),
            defaultValue: [String](),
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.system-extension.install",
            name: "Install System Extensions",
            explanation: "Lets the app install and update system extensions without repeated user approval prompts.",
            symbol: "square.and.arrow.down.fill",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),

        // MARK: Notifications & Communication
        CapabilityDefinition(
            rawKey: "com.apple.developer.usernotifications.critical-alerts",
            name: "Critical Alerts",
            explanation: "Allows the app to play sounds and bypass the mute switch or Do Not Disturb for critical notifications.",
            symbol: "bell.badge.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.usernotifications.time-sensitive",
            name: "Time-Sensitive Notifications",
            explanation: "Allows notifications to break through Focus filters immediately.",
            symbol: "alarm.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.usernotifications.communication",
            name: "Communication Notifications",
            explanation: "Identifies incoming communication alerts with caller avatars and direct reply shortcuts.",
            symbol: "message.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),

        // MARK: Networking & Hardware
        CapabilityDefinition(
            rawKey: "com.apple.developer.networking.wifi-info",
            name: "Access Wi-Fi Information",
            explanation: "Allows the app to obtain the Wi-Fi network name (SSID) and BSSID.",
            symbol: "wifi",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.networking.HotspotConfiguration",
            name: "Hotspot Configuration",
            explanation: "Lets the app configure and connect to Wi-Fi networks and personal hotspots programmatically.",
            symbol: "personalhotspot",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.networking.multipath",
            name: "Multipath Networking",
            explanation: "Allows the app to use Multipath TCP to seamlessly transition between Wi-Fi and Cellular.",
            symbol: "arrow.triangle.swap",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.nfc.readersession.formats",
            name: "NFC Tag Reading",
            explanation: "Allows reading and writing NFC tags using Core NFC. List supported tag formats (e.g. NDEF, TAG).",
            symbol: "wave.3.forward.circle.fill",
            section: .services,
            payload: .fixedValueList(allowed: ["NDEF", "TAG", "PACE"]),
            defaultValue: ["NDEF"]
        ),

        // MARK: Modern Frameworks & System
        CapabilityDefinition(
            rawKey: "com.apple.developer.weatherkit",
            name: "WeatherKit",
            explanation: "Grants access to global weather data and forecasts from the Apple Weather service.",
            symbol: "cloud.sun.rain.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.group-session",
            name: "Group Activities (SharePlay)",
            explanation: "Lets users share experiences in real-time with FaceTime callers via SharePlay.",
            symbol: "person.2.wave.2.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.family-controls",
            name: "Family Controls",
            explanation: "Authorizes the app to administer parental controls, content filters, and app restrictions.",
            symbol: "figure.2.and.child.holdinghands",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.device-activity.monitoring",
            name: "Screen Time & Device Activity",
            explanation: "Enables monitoring app and web usage schedules and shield configurations.",
            symbol: "hourglass",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.authentication-services.autofill-credential-provider",
            name: "AutoFill Credential Provider",
            explanation: "Provides credentials and passkeys directly into Safari and other apps via AutoFill.",
            symbol: "key.viewfinder",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.kernel.extended-virtual-addressing",
            name: "Extended Virtual Addressing",
            explanation: "Provides access to a larger virtual address space on 64-bit systems.",
            symbol: "memorychip.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.kernel.increased-memory-limit",
            name: "Increased Memory Limit",
            explanation: "Informs the operating system that your app may exceed the default per-app memory budget.",
            symbol: "chart.bar.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.background-assets",
            name: "Background Assets",
            explanation: "Allows downloading essential game or app asset packs in the background prior to launch.",
            symbol: "arrow.down.circle.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.storekit.external-purchase",
            name: "StoreKit External Purchase",
            explanation: "Enables offering digital goods using an external payment processor where permitted.",
            symbol: "cart.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),

        // MARK: Additional Sandbox Security
        CapabilityDefinition(
            rawKey: "com.apple.security.automation.apple-events",
            name: "Apple Events Automation",
            explanation: "Allows the sandboxed app to send Apple Events to other scriptable applications.",
            symbol: "applescript.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.smartcard",
            name: "Smart Card Access",
            explanation: "Allows the app to communicate with inserted cryptographic smart cards and tokens.",
            symbol: "creditcard",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.serial",
            name: "Serial Ports",
            explanation: "Grants access to serial communication interfaces (RS-232, serial modems).",
            symbol: "cable.connector.horizontal",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),

        // MARK: - Advanced App Sandbox
        CapabilityDefinition(
            rawKey: "com.apple.security.files.bookmarks.app-scope",
            name: "Security-Scoped Bookmarks (App-Scope)",
            explanation: "Allows the sandboxed app to create and resolve app-scoped bookmarks to retain file access across launches.",
            symbol: "bookmark.fill",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.bookmarks.document-scope",
            name: "Security-Scoped Bookmarks (Document-Scope)",
            explanation: "Allows the app to embed document-scoped bookmarks referencing external assets inside saved project files.",
            symbol: "doc.badge.plus",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.files.all",
            name: "All Files Access (Temporary Exception)",
            explanation: "Grants broad read-write access to files across the entire filesystem. Requires explicit App Store justification.",
            symbol: "externaldrive.badge.xmark",
            section: .sandbox,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.scripting-targets",
            name: "AppleScript Scripting Targets",
            explanation: "Authorizes the sandboxed app to send Apple Events to specific designated scriptable applications.",
            symbol: "applescript",
            section: .sandbox,
            payload: .idList(placeholder: "com.apple.mail"),
            defaultValue: [String]()
        ),

        // MARK: - Advanced Hardened Runtime
        CapabilityDefinition(
            rawKey: "com.apple.security.cs.disable-executable-page-protection",
            name: "Disable Executable Page Protection",
            explanation: "Allows modifying memory pages marked as executable without unmapping first. Required by certain JIT runtimes.",
            symbol: "shield.slash",
            section: .hardenedRuntime,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.get-task-allow",
            name: "Debugging Permissions (Get Task Allow)",
            explanation: "Permits debuggers and profilers like LLDB and Instruments to attach to the application process.",
            symbol: "ant.fill",
            section: .hardenedRuntime,
            payload: .none,
            defaultValue: true
        ),

        // MARK: - Advanced iCloud & Push
        CapabilityDefinition(
            rawKey: "com.apple.developer.icloud-container-development-container-identifiers",
            name: "iCloud Development Containers",
            explanation: "Specifies custom container identifiers used when testing against the iCloud Development sandbox environment.",
            symbol: "icloud.and.arrow.down",
            section: .cloud,
            payload: .idList(placeholder: "iCloud.com.example.app"),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.usernotifications.filtering",
            name: "Notification Service Filtering",
            explanation: "Authorizes the Notification Service Extension to inspect and suppress incoming remote push notifications before display.",
            symbol: "line.3.horizontal.decrease.circle.fill",
            section: .cloud,
            payload: .none,
            defaultValue: true
        ),

        // MARK: - Advanced Sharing
        CapabilityDefinition(
            rawKey: "keychain-cloud-circle",
            name: "iCloud Keychain Synchronization",
            explanation: "Enables synchronizing credentials and tokens stored in the Keychain across the user's iCloud devices.",
            symbol: "key.icloud.fill",
            section: .sharing,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.shared-web-credentials",
            name: "Shared Web Credentials",
            explanation: "Allows sharing username and password credentials seamlessly between this app and your websites.",
            symbol: "globe.badge.chevron.backward",
            section: .sharing,
            payload: .idList(placeholder: "example.com"),
            defaultValue: [String]()
        ),

        // MARK: - Advanced Personal Information
        CapabilityDefinition(
            rawKey: "com.apple.security.personal-information.reminders",
            name: "Reminders Access",
            explanation: "Allows the sandboxed app to read and create reminders in the user's Reminders store.",
            symbol: "list.bullet.clipboard.fill",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.healthkit.access",
            name: "HealthKit Clinical Records",
            explanation: "Allows the app to read health, lab result, and clinical record data with user permission.",
            symbol: "cross.case.fill",
            section: .personal,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.healthkit.background-delivery",
            name: "HealthKit Background Delivery",
            explanation: "Enables background observation updates when new health records or sample data are recorded.",
            symbol: "heart.text.square.fill",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.contacts.notes",
            name: "Contacts Full Notes Access",
            explanation: "Grants permission to read and write note fields on contacts. Requires Apple approval.",
            symbol: "note.text",
            section: .personal,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.sensorkit.reader.allow",
            name: "SensorKit Data",
            explanation: "Enables ambient sensor and device usage telemetry for approved health research studies.",
            symbol: "sensor.fill",
            section: .personal,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),

        // MARK: - Modern Apple Services & Hardware
        CapabilityDefinition(
            rawKey: "com.apple.developer.carkey",
            name: "CarKey Digital Keys",
            explanation: "Allows the device to store digital car keys, lock, unlock, and start compatible vehicles.",
            symbol: "car.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.matter.allow-setup-payload",
            name: "Matter Accessory Setup",
            explanation: "Enables discovering, commissioning, and controlling Matter smart accessories in HomeKit ecosystems.",
            symbol: "m.circle.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.carplay-audio",
            name: "CarPlay Audio",
            explanation: "Enables CarPlay dashboard integration for audio streaming and podcast playback apps.",
            symbol: "car.side.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.carplay-navigation",
            name: "CarPlay Navigation",
            explanation: "Enables CarPlay dashboard turn-by-turn navigation displays and audio prompts.",
            symbol: "arrow.triangle.turn.up.right.diamond.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.carplay-messaging",
            name: "CarPlay Messaging",
            explanation: "Allows communication and messaging apps to compose and read messages via Siri in CarPlay.",
            symbol: "message.and.waveform.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.classkit-environment",
            name: "ClassKit Environment",
            explanation: "Authorizes the app to create educational activities and submit student progress to Schoolwork.",
            symbol: "graduationcap.fill",
            section: .services,
            payload: .choice(options: ["development", "production"]),
            defaultValue: "development"
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.push-to-talk",
            name: "Push to Talk (PTT)",
            explanation: "Enables real-time half-duplex Walkie-Talkie style voice transmission with system background channels.",
            symbol: "speaker.wave.2.bubble.left.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.storekit.external-link.account",
            name: "StoreKit External Link Account",
            explanation: "Allows reader apps to include links to external websites for account creation and subscription management.",
            symbol: "arrow.up.right.square.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.storekit.external-purchase-link",
            name: "StoreKit External Purchase Link",
            explanation: "Authorizes linking to external payment options where permitted by regional regulations.",
            symbol: "creditcard.and.123",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.live-activities",
            name: "Live Activities Background Updates",
            explanation: "Allows pushing real-time dynamic ActivityKit updates to the Dynamic Island and Lock Screen.",
            symbol: "waveform.path.badge.plus",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "inter-app-audio",
            name: "Inter-App Audio",
            explanation: "Allows real-time audio and MIDI streaming between compatible audio synthesis and effects apps.",
            symbol: "hifispeaker.2.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.camera.spatial-video",
            name: "Spatial Video Capture",
            explanation: "Enables recording spatial stereoscopic video on supported hardware devices.",
            symbol: "video.badge.plus",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.accessory-setup-kit",
            name: "AccessorySetupKit",
            explanation: "Allows seamless discovery and pairing of Bluetooth and Wi-Fi accessories without privacy alerts.",
            symbol: "antenna.radiowaves.left.and.right.circle.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.journal.media-donation",
            name: "Journaling Suggestions Donation",
            explanation: "Enables donating workouts, photos, and location visits to iOS Journaling suggestions.",
            symbol: "book.pages.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.translation",
            name: "System Translation",
            explanation: "Provides access to system on-device and cloud translation capabilities via Translation framework.",
            symbol: "character.bubble.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),

        // MARK: - DriverKit & System Extensions
        CapabilityDefinition(
            rawKey: "com.apple.developer.driverkit.transport.usb",
            name: "DriverKit USB Transport",
            explanation: "Allows user-space drivers to communicate directly with USB hardware.",
            symbol: "cable.connector",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.driverkit.transport.hid",
            name: "DriverKit HID Transport",
            explanation: "Allows user-space drivers to control Human Interface Devices like game controllers, keyboards, and mice.",
            symbol: "gamecontroller",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.driverkit.transport.serial",
            name: "DriverKit Serial Transport",
            explanation: "Permits user-space DriverKit extensions to interface with serial bus hardware and converters.",
            symbol: "cable.connector.horizontal",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.driverkit.family.scsi",
            name: "DriverKit SCSI Storage Family",
            explanation: "Allows user-space device drivers for SCSI controllers and mass-storage devices.",
            symbol: "externaldrive.fill.badge.checkmark",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.driverkit.family.networking",
            name: "DriverKit Ethernet Networking Family",
            explanation: "Allows user-space device drivers for wired Ethernet network interface controllers (NICs).",
            symbol: "network.badge.shield.half.filled",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.driverkit.family.audio",
            name: "DriverKit Audio Family",
            explanation: "Allows developing user-space DriverKit extensions for USB and Thunderbolt audio interfaces.",
            symbol: "speaker.wave.3.fill",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.networking.custom-protocol",
            name: "Custom Network Protocol",
            explanation: "Permits NetworkExtension packet tunnels to implement custom proprietary VPN protocols.",
            symbol: "shield.checkered",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),

        // MARK: - Virtualization & Hypervisor
        CapabilityDefinition(
            rawKey: "com.apple.developer.virtualization",
            name: "Virtualization Framework",
            explanation: "Allows the application to create, configure, and boot virtual machines on macOS.",
            symbol: "desktopcomputer.trianglebadge.exclamationmark",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.hypervisor",
            name: "Hypervisor Framework",
            explanation: "Permits user-space software to manage CPU and memory virtualization directly via Hypervisor.framework.",
            symbol: "cpu.fill",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true
        ),

        // MARK: - Proximity & Contactless Payments
        CapabilityDefinition(
            rawKey: "com.apple.developer.proximity-reader.payment.acceptance",
            name: "Tap to Pay on iPhone",
            explanation: "Enables contactless in-person payment acceptance using ProximityReader on supported iPhones.",
            symbol: "wave.3.forward.circle.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.proximity-reader.identity.acceptance",
            name: "Tap to Present ID",
            explanation: "Allows reading and verifying mobile driver's licenses and state IDs via ProximityReader.",
            symbol: "person.text.rectangle.fill",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.payment-pass-provisioning",
            name: "In-App Card Provisioning",
            explanation: "Allows adding payment cards and transit passes directly to Apple Wallet without user manual entry.",
            symbol: "creditcard.and.123",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),

        // MARK: - Accessories, Hardware & Vision
        CapabilityDefinition(
            rawKey: "com.apple.developer.dock-accessory",
            name: "DockKit Accessory Tracking",
            explanation: "Allows motorized tracking stands and docks to track subjects automatically via DockKit.",
            symbol: "video.badge.waveform",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.cameracapture",
            name: "Headless Camera Capture",
            explanation: "Permits specialized camera capture without active viewfinders on visionOS and enterprise macOS.",
            symbol: "camera.viewfinder",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.carplay-charging",
            name: "CarPlay EV Charging",
            explanation: "Allows navigation and charging station discovery for electric vehicles within Apple CarPlay.",
            symbol: "bolt.car.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.carplay-parking",
            name: "CarPlay Parking",
            explanation: "Enables parking location finders, reservations, and payment assistance inside Apple CarPlay.",
            symbol: "parkingsign.circle.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),

        // MARK: - Streaming, Fonts & Media Analysis
        CapabilityDefinition(
            rawKey: "com.apple.developer.coremedia.hls.low-latency",
            name: "Low-Latency HLS",
            explanation: "Allows video streaming playback and publishing using Apple's sub-second Low-Latency HLS standard.",
            symbol: "play.tv.fill",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.media-analysis",
            name: "Media Analysis Engine",
            explanation: "Provides accelerated media analysis and computer vision processing pipelines via Vision framework.",
            symbol: "waveform.path.badge.plus",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.user-fonts",
            name: "Custom Font Provider",
            explanation: "Enables font management applications to register and install custom fonts for system-wide app usage.",
            symbol: "textformat",
            section: .personal,
            payload: .none,
            defaultValue: true
        ),

        // MARK: - System Extensions & Credential Providers
        CapabilityDefinition(
            rawKey: "com.apple.developer.system-extension.install",
            name: "System Extension Installation",
            explanation: "Allows macOS applications to install driver, network, and endpoint security system extensions.",
            symbol: "gearshape.arrow.triangle.2.circlepath",
            section: .systemExtensions,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.authentication-services.autofill-credential-provider",
            name: "AutoFill Credential Provider",
            explanation: "Enables third-party password and passkey managers to provide autofill credentials system-wide.",
            symbol: "key.viewfinder",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.identity-lookup",
            name: "SMS & Call Spam Filtering",
            explanation: "Enables IdentityLookup extensions to identify and block nuisance phone calls and SMS spam.",
            symbol: "phone.down.waves.left.and.right",
            section: .services,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.networking.hotspot-helper",
            name: "Hotspot Helper",
            explanation: "Allows negotiating authentication for complex public Wi-Fi networks using NEHotspotHelper.",
            symbol: "wifi.exclamationmark",
            section: .services,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),

        // MARK: - HealthKit & SensorKit Telemetry
        CapabilityDefinition(
            rawKey: "com.apple.developer.healthkit.recalibrate-estimates",
            name: "HealthKit Recalibrate Estimates",
            explanation: "Allows authorized clinical and research applications to request recalibration of health baseline metrics.",
            symbol: "heart.text.square",
            section: .personal,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.sensorkit.ambient-light-sensor",
            name: "SensorKit Ambient Light Sensor",
            explanation: "Provides access to ambient illuminance and chromaticity telemetry for approved research studies.",
            symbol: "sun.max.trianglebadge.exclamationmark",
            section: .personal,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.sensorkit.device-usage",
            name: "SensorKit Device Usage Telemetry",
            explanation: "Provides device unlock counts, app category usage, and notification metrics for behavioral health research.",
            symbol: "chart.bar.xaxis",
            section: .personal,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.developer.sensorkit.speech-metrics",
            name: "SensorKit Speech Metrics",
            explanation: "Provides acoustic speech metrics and vocal biomarker telemetry for cognitive and speech research.",
            symbol: "waveform.and.mic",
            section: .personal,
            payload: .none,
            defaultValue: true,
            requiresSpecialApproval: true
        ),

        // MARK: - App Sandbox Hardware & Preferences
        CapabilityDefinition(
            rawKey: "com.apple.security.device.usb",
            name: "Sandbox USB Device Access",
            explanation: "Enables sandboxed macOS apps to communicate directly with connected USB hardware devices.",
            symbol: "cable.connector.horizontal",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.bluetooth",
            name: "Sandbox Bluetooth Access",
            explanation: "Enables sandboxed macOS apps to discover, pair, and communicate with Bluetooth and BLE peripherals.",
            symbol: "bolt.horizontal.circle",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.device.serial",
            name: "Sandbox Serial Ports",
            explanation: "Permits sandboxed macOS apps to open and transfer data across serial interfaces and UART modems.",
            symbol: "point.3.connected.trianglepath.dotted",
            section: .sandbox,
            payload: .none,
            defaultValue: true
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.temporary-exception.shared-preference.read-only",
            name: "Temporary Exception: Shared Prefs Read-Only",
            explanation: "Grants read-only access to user defaults/preferences from another application domain outside sandbox.",
            symbol: "exclamationmark.shield",
            section: .sandbox,
            payload: .idList(placeholder: "Domain bundle identifier (e.g. com.apple.finder)"),
            defaultValue: [String]()
        ),
        CapabilityDefinition(
            rawKey: "com.apple.security.temporary-exception.shared-preference.read-write",
            name: "Temporary Exception: Shared Prefs Read-Write",
            explanation: "Grants read and write access to user defaults/preferences from another application domain outside sandbox.",
            symbol: "exclamationmark.shield.fill",
            section: .sandbox,
            payload: .idList(placeholder: "Domain bundle identifier (e.g. com.apple.finder)"),
            defaultValue: [String]()
        ),
    ]

    /// All raw entitlement keys managed by capability toggles, including composite keys.
    public static var allRawKeys: [String] {
        var keys = definitions.map(\.rawKey)
        keys.append(contentsOf: definitions.flatMap(\.compositeKeys))
        return keys
    }

    public static func definitions(for section: EntitlementCapabilitySection) -> [CapabilityDefinition] {
        definitions.filter { $0.section == section }
    }
}
