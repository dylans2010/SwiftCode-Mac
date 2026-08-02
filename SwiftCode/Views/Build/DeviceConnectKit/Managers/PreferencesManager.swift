import Foundation
import Observation

@Observable
@MainActor
public final class PreferencesManager {
    public static let shared = PreferencesManager()

    // Configs persisted via UserDefaults
    public var autoDiscover: Bool {
        didSet { UserDefaults.standard.set(autoDiscover, forKey: "com.swiftcode.deviceconnect.autoDiscover") }
    }
    public var autoValidate: Bool {
        didSet { UserDefaults.standard.set(autoValidate, forKey: "com.swiftcode.deviceconnect.autoValidate") }
    }
    public var autoSaveBeforeDeploy: Bool {
        didSet { UserDefaults.standard.set(autoSaveBeforeDeploy, forKey: "com.swiftcode.deviceconnect.autoSaveBeforeDeploy") }
    }
    public var autoLaunch: Bool {
        didSet { UserDefaults.standard.set(autoLaunch, forKey: "com.swiftcode.deviceconnect.autoLaunch") }
    }
    public var autoStreamLogs: Bool {
        didSet { UserDefaults.standard.set(autoStreamLogs, forKey: "com.swiftcode.deviceconnect.autoStreamLogs") }
    }
    public var showNotifications: Bool {
        didSet { UserDefaults.standard.set(showNotifications, forKey: "com.swiftcode.deviceconnect.showNotifications") }
    }
    public var keepHistory: Bool {
        didSet { UserDefaults.standard.set(keepHistory, forKey: "com.swiftcode.deviceconnect.keepHistory") }
    }
    public var maxSessionCount: Int {
        didSet { UserDefaults.standard.set(maxSessionCount, forKey: "com.swiftcode.deviceconnect.maxSessionCount") }
    }

    private init() {
        self.autoDiscover = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoDiscover") as? Bool ?? true
        self.autoValidate = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoValidate") as? Bool ?? true
        self.autoSaveBeforeDeploy = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoSaveBeforeDeploy") as? Bool ?? true
        self.autoLaunch = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoLaunch") as? Bool ?? true
        self.autoStreamLogs = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.autoStreamLogs") as? Bool ?? true
        self.showNotifications = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.showNotifications") as? Bool ?? true
        self.keepHistory = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.keepHistory") as? Bool ?? true
        self.maxSessionCount = UserDefaults.standard.object(forKey: "com.swiftcode.deviceconnect.maxSessionCount") as? Int ?? 50
    }
}
