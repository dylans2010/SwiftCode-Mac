import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum DeviceCommand: String, Sendable, CaseIterable {
    case home, lock, appSwitcher, actionButton, rotateLeft, rotateRight, screenshot, recordScreen
    case volumeUp, volumeDown, resetCamera
    case viewInHeadset
    case zoomIn, zoomOut, zoomToFit, physicalSize, toggleBezels
    case captureKeyboard, start, restart, shutDown, forceShutDown
    case poseClosed, posePartiallyOpen, poseOpen
    case shake, memoryPressure, slowAnimations, standby

    public var title: String {
        switch self {
        case .home: "Home"
        case .lock: "Lock"
        case .appSwitcher: "App Switcher"
        case .actionButton: "Action Button"
        case .rotateLeft: "Rotate Left"
        case .rotateRight: "Rotate Right"
        case .screenshot: "Screenshot"
        case .recordScreen: "Record Screen"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .resetCamera: "Reset Camera"
        case .viewInHeadset: "View in Headset"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .zoomToFit: "Zoom to Fit"
        case .physicalSize: "Physical Size"
        case .toggleBezels: "Hide Bezels"
        case .captureKeyboard: "Keyboard Capture"
        case .start: "Start"
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        case .forceShutDown: "Force Shut Down"
        case .poseClosed: DevicePosture.closed.title
        case .posePartiallyOpen: DevicePosture.halfOpen.title
        case .poseOpen: DevicePosture.openFlat.title
        case .shake: "Shake"
        case .memoryPressure: "Simulate Memory Warning"
        case .slowAnimations: "Slow Animations"
        case .standby: "Standby Mode"
        }
    }

    public var keyEquivalent: (key: String, modifiers: DeviceKeyModifiers)? {
        switch self {
        case .home: ("h", [.command, .shift])
        case .lock: ("l", [.command])
        case .rotateLeft: (DeviceKeyModifiers.leftArrow, [.command])
        case .rotateRight: (DeviceKeyModifiers.rightArrow, [.command])
        case .screenshot: ("s", [.command, .shift])
        case .recordScreen: ("r", [.command, .shift])
        case .volumeUp: (DeviceKeyModifiers.upArrow, [.command, .option])
        case .volumeDown: (DeviceKeyModifiers.downArrow, [.command, .option])
        case .zoomIn: ("+", [.command])
        case .zoomOut: ("-", [.command])
        case .zoomToFit: ("9", [.command])
        case .physicalSize: ("0", [.command])
        case .captureKeyboard: ("k", [.command, .shift])
        case .viewInHeadset: ("h", [.command, .control])
        case .poseClosed: ("1", [.command, .option])
        case .posePartiallyOpen: ("2", [.command, .option])
        case .poseOpen: ("3", [.command, .option])
        case .shake: ("z", [.command, .control])
        case .memoryPressure: ("m", [.command, .shift, .control])
        case .slowAnimations: ("t", [.command])
        default: nil
        }
    }

    public static let controlsMenu: [DeviceCommand?] = [.home, .lock, .appSwitcher, .actionButton, nil, .rotateLeft, .rotateRight,
                                                        nil, .screenshot, .recordScreen, nil, .volumeUp, .volumeDown, .resetCamera,
                                                        .viewInHeadset, nil, .shake, .memoryPressure, .slowAnimations, .standby]
    public static let zoomMenu: [DeviceCommand] = [.zoomIn, .zoomOut, .zoomToFit, .physicalSize]

    public static func bound(to key: String, modifiers: DeviceKeyModifiers) -> DeviceCommand? {
        let k = key.lowercased()
        return allCases.first { c in
            guard let e = c.keyEquivalent else { return false }
            return e.modifiers == modifiers && (e.key == k || (c == .zoomIn && k == "=" ))
        }
    }
}

public struct DeviceKeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = DeviceKeyModifiers(rawValue: 1)
    public static let shift = DeviceKeyModifiers(rawValue: 2)
    public static let option = DeviceKeyModifiers(rawValue: 4)
    public static let control = DeviceKeyModifiers(rawValue: 8)

    public static let upArrow = String(UnicodeScalar(0xF700)!)
    public static let downArrow = String(UnicodeScalar(0xF701)!)
    public static let leftArrow = String(UnicodeScalar(0xF702)!)
    public static let rightArrow = String(UnicodeScalar(0xF703)!)
}

public enum DeviceCaptureNames {
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: date)
    }

    public static func screenshot(device: String, at date: Date, timeZone: TimeZone = .current) -> String {
        "Screenshot \(sanitized(device)) \(timestamp(date, timeZone: timeZone)).png"
    }

    public static func recording(device: String, at date: Date, timeZone: TimeZone = .current) -> String {
        "Screen Recording \(sanitized(device)) \(timestamp(date, timeZone: timeZone)).mov"
    }

    static func sanitized(_ s: String) -> String { s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
}
