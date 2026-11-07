import Foundation
@testable import YcodeIDECore
@testable import YcodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

struct TestDefaults {
    let defaults: UserDefaults
    let suite: String

    init(_ name: String = "defaults") {
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/defaults")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suite = dir.appendingPathComponent("\(name)-\(UUID().uuidString)").path
        defaults = UserDefaults(suiteName: suite)!
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(atPath: suite + ".plist")
    }
}

@MainActor
final class IsolatedPreferences {
    private let t: TestDefaults
    private let old = Preferences.shared
    private let dir: URL

    init(_ name: String) {
        t = TestDefaults(name)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-prefs-\(UUID().uuidString)")
        Preferences.shared = Preferences(defaults: t.defaults, themesDirectory: dir.appendingPathComponent("Themes"))
    }

    func restore() {
        Preferences.shared = old
        t.remove()
        try? FileManager.default.removeItem(at: dir)
    }
}
