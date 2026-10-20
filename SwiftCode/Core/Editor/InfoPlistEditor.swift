import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.Core", category: "InfoPlistEditor")

// MARK: - Models

public struct InfoPlistNSString: Sendable, Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let category: String
    public let description: String
    public let sfSymbol: String
    public let valueType: ValueType
    public let recommendedWording: String
    public let searchKeywords: [String]

    public enum ValueType: String, Sendable, CaseIterable {
        case string = "String"
        case boolean = "Boolean"
        case array = "Array"
        case dictionary = "Dictionary"
        case number = "Number"
        case date = "Date"
    }
}

public struct InfoPlistNSStrings: Sendable {
    public static let all: [InfoPlistNSString] = [
        InfoPlistNSString(
            key: "NSCameraUsageDescription",
            name: "Camera Usage Description",
            category: "Privacy - Camera",
            description: "Required to let the application capture photos and videos inside the app.",
            sfSymbol: "camera.fill",
            valueType: .string,
            recommendedWording: "This app requires camera access to scan barcodes and take user profile photos.",
            searchKeywords: ["camera", "photo", "video", "capture"]
        ),
        InfoPlistNSString(
            key: "NSMicrophoneUsageDescription",
            name: "Microphone Usage Description",
            category: "Privacy - Microphone",
            description: "Required to record audio with video captures or for voice interaction features.",
            sfSymbol: "mic.fill",
            valueType: .string,
            recommendedWording: "This app requires microphone access to record audio messages.",
            searchKeywords: ["microphone", "audio", "record", "voice"]
        ),
        InfoPlistNSString(
            key: "NSPhotoLibraryUsageDescription",
            name: "Photo Library Usage Description",
            category: "Privacy - Photo Library",
            description: "Required to let the user choose existing photos from their library to use in the app.",
            sfSymbol: "photo.fill",
            valueType: .string,
            recommendedWording: "This app requires photo library access to upload a custom avatar.",
            searchKeywords: ["photo", "library", "album", "image"]
        ),
        InfoPlistNSString(
            key: "NSPhotoLibraryAddUsageDescription",
            name: "Photo Library Additions",
            category: "Privacy - Photo Library Additions",
            description: "Required to let the app save newly generated images directly into the library.",
            sfSymbol: "photo.badge.plus",
            valueType: .string,
            recommendedWording: "This app requires permission to save photos to your library.",
            searchKeywords: ["photo", "library", "add", "save"]
        ),
        InfoPlistNSString(
            key: "NSContactsUsageDescription",
            name: "Contacts Usage Description",
            category: "Privacy - Contacts",
            description: "Required to let users find contacts who are already using the app or invite new ones.",
            sfSymbol: "person.2.fill",
            valueType: .string,
            recommendedWording: "This app requires contacts access to connect you with friends.",
            searchKeywords: ["contacts", "address book", "friends", "invite"]
        ),
        InfoPlistNSString(
            key: "NSCalendarsUsageDescription",
            name: "Calendars Usage Description",
            category: "Privacy - Calendars",
            description: "Required to let users schedule events and manage calendar items.",
            sfSymbol: "calendar",
            valueType: .string,
            recommendedWording: "This app requires calendar access to book events.",
            searchKeywords: ["calendar", "schedule", "events"]
        ),
        InfoPlistNSString(
            key: "NSRemindersUsageDescription",
            name: "Reminders Usage Description",
            category: "Privacy - Reminders",
            description: "Required to let users create and manage custom alerts inside the system Reminders app.",
            sfSymbol: "list.bullet.rectangle",
            valueType: .string,
            recommendedWording: "This app requires access to Reminders to add tasks.",
            searchKeywords: ["reminders", "tasks", "alerts"]
        ),
        InfoPlistNSString(
            key: "NSLocationAlwaysUsageDescription",
            name: "Location Always",
            category: "Privacy - Location Always",
            description: "Required for continuous background location updates.",
            sfSymbol: "location.fill",
            valueType: .string,
            recommendedWording: "This app requires background location access to provide real-time updates.",
            searchKeywords: ["location", "gps", "always", "background"]
        ),
        InfoPlistNSString(
            key: "NSLocationWhenInUseUsageDescription",
            name: "Location When In Use",
            category: "Privacy - Location When In Use",
            description: "Required to access user location while the app is active in the foreground.",
            sfSymbol: "location",
            valueType: .string,
            recommendedWording: "This app requires location access to find nearby services.",
            searchKeywords: ["location", "gps", "when in use", "foreground"]
        ),
        InfoPlistNSString(
            key: "NSLocationAlwaysAndWhenInUseUsageDescription",
            name: "Location Always & When In Use",
            category: "Privacy - Location Always & When In Use",
            description: "Required to access location both in the foreground and background.",
            sfSymbol: "location.north.fill",
            valueType: .string,
            recommendedWording: "This app requires location access to track active trips in real time.",
            searchKeywords: ["location", "gps", "always", "background", "foreground"]
        ),
        InfoPlistNSString(
            key: "NSBluetoothAlwaysUsageDescription",
            name: "Bluetooth Always",
            category: "Privacy - Bluetooth",
            description: "Required to communicate with Bluetooth accessories in the background.",
            sfSymbol: "bolt.horizontal.fill",
            valueType: .string,
            recommendedWording: "This app requires Bluetooth access to connect with smart devices.",
            searchKeywords: ["bluetooth", "accessory", "connect"]
        ),
        InfoPlistNSString(
            key: "NSBluetoothPeripheralUsageDescription",
            name: "Bluetooth Peripheral",
            category: "Privacy - Bluetooth Peripheral",
            description: "Required to act as a Bluetooth peripheral and broadcast signals.",
            sfSymbol: "bluetooth",
            valueType: .string,
            recommendedWording: "This app requires Bluetooth peripheral capabilities to sync with other phones.",
            searchKeywords: ["bluetooth", "peripheral", "broadcast", "sync"]
        ),
        InfoPlistNSString(
            key: "NSMotionUsageDescription",
            name: "Motion Usage Description",
            category: "Privacy - Motion",
            description: "Required to monitor user acceleration and movement data.",
            sfSymbol: "figure.walk",
            valueType: .string,
            recommendedWording: "This app requires motion access to count your steps.",
            searchKeywords: ["motion", "steps", "sensor", "acceleration"]
        ),
        InfoPlistNSString(
            key: "NSFaceIDUsageDescription",
            name: "Face ID Usage Description",
            category: "Privacy - Face ID",
            description: "Required to use biometric authentication for secure access.",
            sfSymbol: "faceid",
            valueType: .string,
            recommendedWording: "This app uses Face ID to safely unlock your encrypted wallet.",
            searchKeywords: ["faceid", "biometrics", "secure", "auth"]
        ),
        InfoPlistNSString(
            key: "NSSpeechRecognitionUsageDescription",
            name: "Speech Recognition Description",
            category: "Privacy - Speech Recognition",
            description: "Required to process voice commands and transcribe audio input.",
            sfSymbol: "waveform",
            valueType: .string,
            recommendedWording: "This app requires speech recognition to transcribe voice notes.",
            searchKeywords: ["speech", "recognition", "voice", "transcribe"]
        ),
        InfoPlistNSString(
            key: "NSLocalNetworkUsageDescription",
            name: "Local Network Usage",
            category: "Privacy - Local Network",
            description: "Required to search for and connect to devices on your local network.",
            sfSymbol: "network",
            valueType: .string,
            recommendedWording: "This app requires access to your local network to discover companion devices.",
            searchKeywords: ["local network", "lan", "wifi", "network"]
        ),
        InfoPlistNSString(
            key: "NSUserTrackingUsageDescription",
            name: "User Tracking Usage Description",
            category: "Privacy - Tracking",
            description: "Required to track user activity across apps and websites owned by other companies.",
            sfSymbol: "person.and.arrow.left.and.arrow.right",
            valueType: .string,
            recommendedWording: "We use your data to show you relevant, personalized recommendations.",
            searchKeywords: ["tracking", "idfa", "privacy", "ads"]
        ),
        InfoPlistNSString(
            key: "NSDesktopFolderUsageDescription",
            name: "Desktop Folder Access",
            category: "Privacy - Desktop Folder",
            description: "Required to read or write files directly in the user's Desktop folder on macOS.",
            sfSymbol: "desktopcomputer",
            valueType: .string,
            recommendedWording: "This app needs access to your desktop to organize and save project exports.",
            searchKeywords: ["desktop", "macos", "files", "folder"]
        ),
        InfoPlistNSString(
            key: "NSDownloadsFolderUsageDescription",
            name: "Downloads Folder Access",
            category: "Privacy - Downloads Folder",
            description: "Required to read or write files directly in the user's Downloads folder on macOS.",
            sfSymbol: "square.and.arrow.down",
            valueType: .string,
            recommendedWording: "This app needs access to your downloads folder to save generated assets.",
            searchKeywords: ["downloads", "macos", "files", "folder"]
        ),
        InfoPlistNSString(
            key: "NSDocumentsFolderUsageDescription",
            name: "Documents Folder Access",
            category: "Privacy - Documents Folder",
            description: "Required to read or write files directly in the user's Documents folder on macOS.",
            sfSymbol: "doc.on.folder",
            valueType: .string,
            recommendedWording: "This app needs access to your documents folder to load your saved workspaces.",
            searchKeywords: ["documents", "macos", "files", "folder"]
        ),
        InfoPlistNSString(
            key: "NSRemovableVolumesUsageDescription",
            name: "Removable Volumes Access",
            category: "Privacy - Removable Volumes",
            description: "Required to read or write files on connected USB flash drives or external HDDs.",
            sfSymbol: "externaldrive.fill",
            valueType: .string,
            recommendedWording: "This app needs access to external removable drives to back up source code.",
            searchKeywords: ["removable", "usb", "external drive", "volume"]
        ),
        InfoPlistNSString(
            key: "NSNetworkVolumesUsageDescription",
            name: "Network Volumes Access",
            category: "Privacy - Network Volumes",
            description: "Required to read or write files located on shared network servers.",
            sfSymbol: "server.rack",
            valueType: .string,
            recommendedWording: "This app needs network volume access to save to your local NAS server.",
            searchKeywords: ["network volume", "server", "nas", "share"]
        ),
        InfoPlistNSString(
            key: "NSAppleMusicUsageDescription",
            name: "Apple Music & Media Library",
            category: "Privacy - Media Library",
            description: "Required to access user music library, playlists, and media playback.",
            sfSymbol: "music.note.house.fill",
            valueType: .string,
            recommendedWording: "This app requires access to your Apple Music library to create and play custom audio playlists.",
            searchKeywords: ["music", "media", "apple music", "library", "audio", "playlists"]
        ),
        InfoPlistNSString(
            key: "NSHealthShareUsageDescription",
            name: "HealthKit (Read Data)",
            category: "Privacy - Health",
            description: "Required to read user health, fitness, and wellness metrics from HealthKit.",
            sfSymbol: "heart.fill",
            valueType: .string,
            recommendedWording: "This app reads your activity, step count, and workout history to display wellness analytics.",
            searchKeywords: ["health", "fitness", "healthkit", "workout", "steps", "heart", "read"]
        ),
        InfoPlistNSString(
            key: "NSHealthUpdateUsageDescription",
            name: "HealthKit (Write Data)",
            category: "Privacy - Health",
            description: "Required to record workout, mindfulness, and nutrition metrics into HealthKit.",
            sfSymbol: "heart.text.square.fill",
            valueType: .string,
            recommendedWording: "This app writes your completed workout sessions and active calories directly into Apple Health.",
            searchKeywords: ["health", "workout", "record", "write", "save", "calories"]
        ),
        InfoPlistNSString(
            key: "NSHealthClinicalHealthRecordsShareUsageDescription",
            name: "Clinical Health Records",
            category: "Privacy - Health",
            description: "Required to securely access user clinical lab results and immunization records.",
            sfSymbol: "cross.case.fill",
            valueType: .string,
            recommendedWording: "This app allows you to view and organize your clinical lab results and immunization history securely.",
            searchKeywords: ["clinical", "records", "medical", "doctor", "health", "lab"]
        ),
        InfoPlistNSString(
            key: "NSHomeKitUsageDescription",
            name: "HomeKit Accessories",
            category: "Privacy - HomeKit",
            description: "Required to discover, configure, and automate HomeKit smart home accessories.",
            sfSymbol: "house.fill",
            valueType: .string,
            recommendedWording: "This app connects to your HomeKit accessories to automate lighting and room environments.",
            searchKeywords: ["homekit", "home", "smart accessories", "lights", "iot", "automation"]
        ),
        InfoPlistNSString(
            key: "NSSiriUsageDescription",
            name: "Siri & Shortcuts",
            category: "Privacy - Siri",
            description: "Required to process voice commands and handle app shortcuts using Siri.",
            sfSymbol: "waveform.badge.magnifyingglass",
            valueType: .string,
            recommendedWording: "This app uses Siri to let you execute quick voice actions and shortcuts hands-free.",
            searchKeywords: ["siri", "voice", "shortcuts", "assistant", "intent"]
        ),
        InfoPlistNSString(
            key: "NSNFCReaderUsageDescription",
            name: "NFC Tag Reading",
            category: "Privacy - NFC",
            description: "Required to scan and interact with NFC tags, smart posters, and contactless cards.",
            sfSymbol: "wave.3.forward.circle.fill",
            valueType: .string,
            recommendedWording: "This app needs NFC access to scan smart tags and configure nearby accessories.",
            searchKeywords: ["nfc", "tag", "rfid", "contactless", "scan", "reader"]
        ),
        InfoPlistNSString(
            key: "NSNearbyInteractionUsageDescription",
            name: "Nearby Interaction (Ultra Wideband)",
            category: "Privacy - Nearby Interaction",
            description: "Required to measure precise distance and direction to nearby devices using UWB.",
            sfSymbol: "location.viewfinder",
            valueType: .string,
            recommendedWording: "This app uses Ultra Wideband to show precise distance and direction to nearby companion devices.",
            searchKeywords: ["nearby", "uwb", "ultra wideband", "direction", "distance", "spatial"]
        ),
        InfoPlistNSString(
            key: "NSNearbyInteractionAllowOnceUsageDescription",
            name: "Nearby Interaction (One-Time)",
            category: "Privacy - Nearby Interaction",
            description: "Required for one-time sessions measuring distance to nearby companion accessories.",
            sfSymbol: "location.viewfinder",
            valueType: .string,
            recommendedWording: "This app uses Ultra Wideband to locate your lost items nearby during this session.",
            searchKeywords: ["nearby", "uwb", "once", "find", "locate"]
        ),
        InfoPlistNSString(
            key: "NSFocusStatusUsageDescription",
            name: "Focus Status",
            category: "Privacy - Focus",
            description: "Required to check whether the user has active Focus modes silencing notifications.",
            sfSymbol: "moon.stars.fill",
            valueType: .string,
            recommendedWording: "This app checks your Focus status so teammates know when your notifications are silenced.",
            searchKeywords: ["focus", "dnd", "do not disturb", "status", "silenced", "modes"]
        ),
        InfoPlistNSString(
            key: "NSAppleEventsUsageDescription",
            name: "Apple Events (macOS Scripting)",
            category: "Privacy - Apple Events",
            description: "Required on macOS to send Apple Events and script other desktop applications.",
            sfSymbol: "applescript",
            valueType: .string,
            recommendedWording: "This app requires Apple Events access to automate workflows in Finder, Xcode, and Terminal.",
            searchKeywords: ["applescript", "apple events", "automate", "macos", "scripting", "terminal"]
        ),
        InfoPlistNSString(
            key: "NSSystemAdministrationUsageDescription",
            name: "System Administration",
            category: "Privacy - System Administration",
            description: "Required to perform privileged system administration and configuration operations.",
            sfSymbol: "wrench.and.screwdriver.fill",
            valueType: .string,
            recommendedWording: "This app requires administrative privileges to install background toolchains and services.",
            searchKeywords: ["admin", "root", "privileged", "system administration", "install"]
        ),
        InfoPlistNSString(
            key: "NSFallDetectionUsageDescription",
            name: "Fall Detection",
            category: "Privacy - Fall Detection",
            description: "Required to receive fall detection events and emergency trigger alerts on Apple Watch.",
            sfSymbol: "figure.fall",
            valueType: .string,
            recommendedWording: "This app monitors fall detection events to notify your emergency contacts immediately.",
            searchKeywords: ["fall", "emergency", "safety", "watch", "health"]
        ),
        InfoPlistNSString(
            key: "NSCriticalAlertUsageDescription",
            name: "Critical Alerts",
            category: "Privacy - Critical Alerts",
            description: "Required to explain why the app sends urgent medical or emergency alarms bypassing mute.",
            sfSymbol: "exclamationmark.triangle.fill",
            valueType: .string,
            recommendedWording: "This app delivers critical security alarms that sound even when Do Not Disturb is active.",
            searchKeywords: ["critical", "alert", "alarm", "emergency", "bypass", "sound"]
        ),
        InfoPlistNSString(
            key: "NSSensorKitUsageDescription",
            name: "SensorKit Research",
            category: "Privacy - SensorKit",
            description: "Required to collect approved ambient telemetry for medical and scientific research studies.",
            sfSymbol: "sensor.fill",
            valueType: .string,
            recommendedWording: "This app collects sensor telemetry for the university health and sleep research study.",
            searchKeywords: ["sensor", "sensorkit", "research", "telemetry", "study"]
        ),
        InfoPlistNSString(
            key: "NSCameraPostureUsageDescription",
            name: "Camera Posture & Spatial Tracking",
            category: "Privacy - Camera Posture",
            description: "Required on visionOS and macOS to access camera position and posture tracking data.",
            sfSymbol: "visionpro",
            valueType: .string,
            recommendedWording: "This app uses camera posture data to position interactive spatial windows in your space.",
            searchKeywords: ["camera", "posture", "spatial", "visionos", "tracking"]
        )
    ]
}

// MARK: - InfoPlistEditor Class

@Observable
@MainActor
public final class InfoPlistEditor: Sendable {
    public let fileURL: URL
    public var entries: [String: Any] = [:]
    public var isDirty: Bool = false

    private var initialEntries: [String: Any] = [:]
    private var undoStack: [[String: Any]] = []
    private var redoStack: [[String: Any]] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    public func load() {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
            logger.warning("No plist file found at \(self.fileURL.path). Starting empty.")
            self.entries = [:]
            self.initialEntries = [:]
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            if let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                self.entries = dict
                self.initialEntries = dict
                logger.info("Successfully loaded Info.plist with \(dict.count) root entries from \(self.fileURL.path, privacy: .public).")
            } else {
                logger.error("Loaded plist is not a valid [String: Any] dictionary.")
            }
        } catch {
            logger.error("Failed to parse Info.plist: \(error.localizedDescription)")
        }
    }

    public func save() throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            throw NSError(domain: "InfoPlistEditor", code: 400, userInfo: [NSLocalizedDescriptionKey: "The target path is a directory, not an Info.plist file: \(fileURL.lastPathComponent)"])
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Automatically order / sort keys before saving
        let sortedEntries = sortDictionary(entries)
        let data = try PropertyListSerialization.data(fromPropertyList: sortedEntries, format: .xml, options: 0)
        try data.write(to: fileURL, options: .atomic)
        self.initialEntries = entries
        self.isDirty = false
        self.undoStack.removeAll()
        self.redoStack.removeAll()
        logger.info("Successfully saved Info.plist to \(self.fileURL.path, privacy: .public).")
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

    public func set(key: String, value: Any) {
        recordUndo()
        entries[key] = value
        checkDirty()
    }

    public func remove(key: String) {
        recordUndo()
        entries.removeValue(forKey: key)
        checkDirty()
    }

    public func addMissingKey(_ key: String) {
        guard entries[key] == nil else { return }
        if let metadata = InfoPlistNSStrings.all.first(where: { $0.key == key }) {
            switch metadata.valueType {
            case .string:
                set(key: key, value: metadata.recommendedWording)
            case .boolean:
                set(key: key, value: true)
            case .array:
                set(key: key, value: [String]())
            case .dictionary:
                set(key: key, value: [String: Any]())
            case .number:
                set(key: key, value: 1)
            case .date:
                set(key: key, value: Date())
            }
        } else {
            set(key: key, value: "")
        }
    }

    public func validateBundleIdentifier(_ bundleID: String) -> Bool {
        let pattern = "^[a-zA-Z0-9.-]+$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: bundleID.utf16.count)
        return regex?.firstMatch(in: bundleID, options: [], range: range) != nil
    }

    public func validateVersion(_ version: String) -> Bool {
        let pattern = "^[0-9]+(\\.[0-9]+)*$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: version.utf16.count)
        return regex?.firstMatch(in: version, options: [], range: range) != nil
    }

    // Advanced capabilities recommendation dictionary validation helper
    public func validatePrivacyKeys() -> [String: String] {
        var issues: [String: String] = [:]
        for key in entries.keys {
            if key.hasSuffix("UsageDescription") {
                if let strVal = entries[key] as? String, strVal.count < 10 {
                    issues[key] = "Description is too short. Apple App Review may reject user-facing descriptions under 10 characters."
                }
            }
        }
        return issues
    }

    public func generateRawXML() -> String {
        let sortedEntries = sortDictionary(entries)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: sortedEntries, format: .xml, options: 0),
              let xmlString = String(data: data, encoding: .utf8) else {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plist version=\"1.0\">\n<dict>\n</dict>\n</plist>"
        }
        return xmlString
    }

    public func updateFromXML(_ xmlString: String) throws {
        guard let data = xmlString.data(using: .utf8) else {
            throw NSError(domain: "InfoPlistEditor", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid XML encoding"])
        }
        if let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            recordUndo()
            self.entries = dict
            checkDirty()
        } else {
            throw NSError(domain: "InfoPlistEditor", code: 400, userInfo: [NSLocalizedDescriptionKey: "XML is not a key-value dictionary structure"])
        }
    }

    // MARK: - Undo / Redo

    private func recordUndo() {
        undoStack.append(entries)
        if undoStack.count > 100 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public func undo() {
        guard !undoStack.isEmpty else { return }
        redoStack.append(entries)
        entries = undoStack.removeLast()
        checkDirty()
    }

    public func redo() {
        guard !redoStack.isEmpty else { return }
        undoStack.append(entries)
        entries = redoStack.removeLast()
        checkDirty()
    }

    private func checkDirty() {
        isDirty = NSDictionary(dictionary: entries) != NSDictionary(dictionary: initialEntries)
    }
}
