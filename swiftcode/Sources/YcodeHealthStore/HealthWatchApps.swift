import Foundation

public enum HealthWatchApps {
    public static func companion(of bundleID: String, deviceData data: String) -> String? {
        let fm = FileManager.default
        let root = data + "/Containers/Bundle/Application"
        for container in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let dir = root + "/" + container
            for app in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where app.hasSuffix(".app") {
                guard let bytes = fm.contents(atPath: dir + "/" + app + "/Info.plist"),
                      let info = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any],
                      info["CFBundleIdentifier"] as? String == bundleID else { continue }
                if let c = info["WKCompanionAppBundleIdentifier"] as? String, !c.isEmpty, c != bundleID { return c }
                return nil
            }
        }
        return nil
    }
}
