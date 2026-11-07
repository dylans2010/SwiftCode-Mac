import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public typealias PlatformWindowID = UInt32

public enum PointerKind: Sendable, Hashable {
    case mouse
    case touch
    case pen
}

public enum PointerPhase: Sendable, Hashable {
    case down
    case moved
    case up
    case cancelled
}

public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let capsLock = KeyModifiers(rawValue: 1 << 4)
    public static let numericPad = KeyModifiers(rawValue: 1 << 5)
}

public struct PointerEvent: Sendable, Equatable {
    public var window: PlatformWindowID
    public var pointer: Int
    public var kind: PointerKind
    public var phase: PointerPhase
    public var location: CGPoint
    public var button: Int
    public var isPressed: Bool
    public var modifiers: KeyModifiers
    public var timestamp: TimeInterval

    public init(window: PlatformWindowID, pointer: Int = 0, kind: PointerKind = .mouse, phase: PointerPhase,
                location: CGPoint, button: Int = 1, isPressed: Bool? = nil, modifiers: KeyModifiers = [],
                timestamp: TimeInterval) {
        self.window = window
        self.pointer = pointer
        self.kind = kind
        self.phase = phase
        self.location = location
        self.button = button
        self.isPressed = isPressed ?? (phase == .down || (phase == .moved && button != 0))
        self.modifiers = modifiers
        self.timestamp = timestamp
    }
}

public struct ScrollEvent: Sendable, Equatable {
    public var window: PlatformWindowID
    public var location: CGPoint
    public var delta: CGSize
    public var isPrecise: Bool
    public var modifiers: KeyModifiers
    public var timestamp: TimeInterval

    public init(window: PlatformWindowID, location: CGPoint, delta: CGSize, isPrecise: Bool = false,
                modifiers: KeyModifiers = [], timestamp: TimeInterval) {
        self.window = window
        self.location = location
        self.delta = delta
        self.isPrecise = isPrecise
        self.modifiers = modifiers
        self.timestamp = timestamp
    }
}

public enum Key: Sendable, Hashable {
    case character(Character)
    case `return`
    case escape
    case backspace
    case tab
    case space
    case deleteForward
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case home
    case end
    case pageUp
    case pageDown
    case clear
    case function(Int)
    case other(UInt32)
}

public struct KeyEvent: Sendable, Hashable {
    public var window: PlatformWindowID
    public var key: Key
    public var isDown: Bool
    public var isRepeat: Bool
    public var modifiers: KeyModifiers
    public var timestamp: TimeInterval

    public init(window: PlatformWindowID, key: Key, isDown: Bool = true, isRepeat: Bool = false,
                modifiers: KeyModifiers = [], timestamp: TimeInterval) {
        self.window = window
        self.key = key
        self.isDown = isDown
        self.isRepeat = isRepeat
        self.modifiers = modifiers
        self.timestamp = timestamp
    }
}

public struct TextInputEvent: Sendable, Hashable {
    public var window: PlatformWindowID
    public var text: String
    public var timestamp: TimeInterval

    public init(window: PlatformWindowID, text: String, timestamp: TimeInterval) {
        self.window = window
        self.text = text
        self.timestamp = timestamp
    }
}

public struct TextEditingEvent: Sendable, Hashable {
    public var window: PlatformWindowID
    public var text: String
    public var cursor: Int
    public var selectionLength: Int
    public var timestamp: TimeInterval

    public init(window: PlatformWindowID, text: String, cursor: Int = 0, selectionLength: Int = 0,
                timestamp: TimeInterval) {
        self.window = window
        self.text = text
        self.cursor = cursor
        self.selectionLength = selectionLength
        self.timestamp = timestamp
    }
}

public enum WindowEventKind: Sendable, Equatable {
    case shown
    case hidden
    case minimized
    case restored
    case resized(CGSize)
    case scaleChanged(Double)
    case focusGained
    case focusLost
    case closeRequested
    case exposed
    case pointerLeft
}

public enum PlatformEvent: Sendable, Equatable {
    case pointer(PointerEvent)
    case scroll(ScrollEvent)
    case key(KeyEvent)
    case textInput(TextInputEvent)
    case textEditing(TextEditingEvent)
    case window(PlatformWindowID, WindowEventKind)
    case openURL(URL)
    case quit
    case settingsChanged
}
