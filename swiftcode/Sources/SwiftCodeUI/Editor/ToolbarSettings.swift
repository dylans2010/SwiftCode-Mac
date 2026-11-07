import Foundation
import Observation

@MainActor
@Observable
public final class ToolbarSettings: Sendable {
    public static let shared = ToolbarSettings()

    public var wordWrap: Bool = false
    public var showSearchBar: Bool = false

    public var showToolNames: Bool {
        didSet {
            UserDefaults.standard.set(showToolNames, forKey: Self.showToolNamesKey)
        }
    }

    private static let showToolNamesKey = "com.swiftcode.toolbar.showToolNames"

    private init() {
        self.showToolNames = UserDefaults.standard.object(forKey: Self.showToolNamesKey) as? Bool ?? true
    }
}
