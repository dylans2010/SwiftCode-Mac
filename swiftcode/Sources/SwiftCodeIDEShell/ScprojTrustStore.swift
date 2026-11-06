import Foundation

/// Finder-opened `.scproj` trust grants (Legacy
/// `ProjectSessionStore.ScprojTrustStore`, ported verbatim). A package is
/// trusted once the user answers "Trust and Open" to the trust alert in
/// `SwiftCodeIDEApp`; trusted paths open without prompting again, and
/// forgetting a grant makes the next open prompt again. This is the
/// single definition of the trust store: the duplicate copy that landed
/// in `SwiftCodeIDECore/Model/ProjectTrustAndDiff.swift` was removed, so
/// unqualified references in files importing both modules (e.g.
/// `SwiftCodeIDEApp`) are unambiguous. Same UserDefaults key and API as
/// Legacy's version.
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
