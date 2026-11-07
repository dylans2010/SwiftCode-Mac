import Foundation

public enum GitBlameSettings {
    public static let showInlineBlameKey = "swiftcode.blame.showInline"
    public static let dateFormatKey = "swiftcode.blame.dateFormat"
    public static let showAuthorAvatarKey = "swiftcode.blame.showAuthorAvatar"

    public enum DateFormat: String, CaseIterable {
        case relative
        case absolute
        case shortHash

        public var displayName: String {
            switch self {
            case .relative: return "Relative"
            case .absolute: return "Absolute"
            case .shortHash: return "Short Hash"
            }
        }
    }

    public static var showInlineBlame: Bool {
        get { UserDefaults.standard.bool(forKey: showInlineBlameKey) }
        set { UserDefaults.standard.set(newValue, forKey: showInlineBlameKey) }
    }

    public static var dateFormat: DateFormat {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dateFormatKey),
                  let format = DateFormat(rawValue: raw) else { return .relative }
            return format
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dateFormatKey) }
    }

    public static var showAuthorAvatar: Bool {
        get { UserDefaults.standard.bool(forKey: showAuthorAvatarKey) }
        set { UserDefaults.standard.set(newValue, forKey: showAuthorAvatarKey) }
    }
}
