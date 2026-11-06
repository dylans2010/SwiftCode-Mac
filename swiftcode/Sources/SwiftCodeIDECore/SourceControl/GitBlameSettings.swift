import Foundation

/// Persisted settings for the editor's Authors (blame) column.
///
/// The settings view (`GitBlameExtensionView` in SwiftCodeUI) binds to the
/// same UserDefaults keys; `GitBlame.annotation` reads the date format and
/// the gutter reads `showInlineBlame` as its initial value, so the settings
/// actually take effect instead of living in un-persisted `@State` (as the
/// Legacy settings view did).
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

    /// Whether new editors open with the Authors column shown.
    public static var showInlineBlame: Bool {
        get { UserDefaults.standard.bool(forKey: showInlineBlameKey) }
        set { UserDefaults.standard.set(newValue, forKey: showInlineBlameKey) }
    }

    /// How blame annotations render the commit date (default `.relative`).
    public static var dateFormat: DateFormat {
        get {
            guard let raw = UserDefaults.standard.string(forKey: dateFormatKey),
                  let format = DateFormat(rawValue: raw) else { return .relative }
            return format
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dateFormatKey) }
    }

    /// Whether blame annotations show the author's avatar. Persisted here;
    /// rendering an avatar in the gutter column is a remaining wiring task
    /// (the gutter draws text annotations today — see `GitBlameExtensionView`).
    public static var showAuthorAvatar: Bool {
        get { UserDefaults.standard.bool(forKey: showAuthorAvatarKey) }
        set { UserDefaults.standard.set(newValue, forKey: showAuthorAvatarKey) }
    }
}
