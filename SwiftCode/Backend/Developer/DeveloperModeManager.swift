import Foundation

final class DeveloperModeManager: ObservableObject, @unchecked Sendable {
    static let shared = DeveloperModeManager()

    @Published var isDeveloperModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDeveloperModeEnabled, forKey: "developer_mode_enabled")
        }
    }

    private init() {
        self.isDeveloperModeEnabled = UserDefaults.standard.bool(forKey: "developer_mode_enabled")
    }

    func enableDeveloperMode() {
        isDeveloperModeEnabled = true
    }
}
