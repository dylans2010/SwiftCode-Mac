public struct HIDUsagePair: Hashable, Sendable, CustomStringConvertible {
    public var page: UInt32
    public var usage: UInt32

    public init(page: UInt32, usage: UInt32) { (self.page, self.usage) = (page, usage) }

    public var description: String { String(format: "0x%X/0x%X", page, usage) }
}

public enum DeviceButtonTable {
    public enum Family: Equatable, Sendable {
        case phone
        case watch(actionButton: Bool)
    }

    public static let home = HIDUsagePair(page: 0x0C, usage: 0x40)
    public static let lock = HIDUsagePair(page: 0x0C, usage: 0x30)
    public static let side = HIDUsagePair(page: 0x0C, usage: 0x95)
    public static let volumeUp = HIDUsagePair(page: 0x0C, usage: 0xE9)
    public static let volumeDown = HIDUsagePair(page: 0x0C, usage: 0xEA)
    public static let watchAction = HIDUsagePair(page: 0xFF01, usage: 0x200)

    public static func usage(of button: DisplayButton, for family: Family) -> HIDUsagePair? {
        switch family {
        case .phone:
            switch button {
            case .home: home
            case .lock: lock
            case .side, .action: side
            case .volumeUp: volumeUp
            case .volumeDown: volumeDown
            }
        case .watch(let actionButton):
            switch button {
            case .home: home
            case .lock: lock
            case .side: side
            case .action: actionButton ? watchAction : nil
            case .volumeUp, .volumeDown: nil
            }
        }
    }

    public static func buttons(for family: Family) -> [DisplayButton] {
        DisplayButton.allCases.filter { usage(of: $0, for: family) != nil }
    }

    public static func watchAccepts(_ pair: HIDUsagePair, actionButton: Bool) -> Bool {
        pair == home || pair == side || pair == lock || (actionButton && pair == watchAction)
    }

    public enum WatchButton: String, CaseIterable, Sendable {
        case crown
        case side
        case action
        case screen

        public var displayButton: DisplayButton {
            switch self {
            case .crown: .home
            case .side: .side
            case .action: .action
            case .screen: .lock
            }
        }

        public init?(named name: String) {
            switch name.lowercased() {
            case "crown", "home", "crown-press": self = .crown
            case "side", "side-button": self = .side
            case "action", "action-button": self = .action
            case "screen", "lock", "wake": self = .screen
            default: return nil
            }
        }
    }
}
