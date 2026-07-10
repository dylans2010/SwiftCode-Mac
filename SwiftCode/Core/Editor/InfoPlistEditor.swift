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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
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
                logger.info("Successfully loaded Info.plist with \(dict.count) root entries.")
            } else {
                logger.error("Loaded plist is not a valid [String: Any] dictionary.")
            }
        } catch {
            logger.error("Failed to parse Info.plist: \(error.localizedDescription)")
        }
    }

    public func save() throws {
        // Automatically order / sort keys before saving
        let sortedEntries = sortDictionary(entries)
        let data = try PropertyListSerialization.data(fromPropertyList: sortedEntries, format: .xml, options: 0)
        try data.write(to: fileURL, options: .atomic)
        self.initialEntries = entries
        self.isDirty = false
        self.undoStack.removeAll()
        self.redoStack.removeAll()
        logger.info("Successfully saved Info.plist.")
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
