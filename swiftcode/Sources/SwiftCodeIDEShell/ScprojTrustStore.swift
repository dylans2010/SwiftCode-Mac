import Foundation

/// Finder-opened `.scproj` trust grants (Legacy
/// `ProjectSessionStore.ScprojTrustStore`, ported verbatim). A package is
/// trusted once the user answers "Trust and Open" to the trust alert in
/// `SwiftCodeIDEApp`; trusted paths open without prompting again, and
/// forgetting a grant makes the next open prompt again. The store lives
/// here (not nested under `ProjectSessionStore`) so the trust flow in
/// `ShellRootView` can use it before that port lands; the services
/// migration owns `ProjectSessionStore` and should re-home or alias this
/// type when it lands rather than keeping two trust stores.
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
