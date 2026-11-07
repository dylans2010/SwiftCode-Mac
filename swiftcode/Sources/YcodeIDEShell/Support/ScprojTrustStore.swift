import Foundation

public enum ScprojTrustStore {
    private static let key = "com.swiftcode.scproj.trustedPaths"

    public static func isTrusted(_ url: URL) -> Bool {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        return paths.contains(url.standardizedFileURL.path)
    }

    public static func markTrusted(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        let path = url.standardizedFileURL.path
        guard !paths.contains(path) else { return }
        paths.append(path)
        UserDefaults.standard.set(paths, forKey: key)
    }

    public static func forget(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.standardizedFileURL.path }
        UserDefaults.standard.set(paths, forKey: key)
    }
}
