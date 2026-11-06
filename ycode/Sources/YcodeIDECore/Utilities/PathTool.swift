import Foundation

/// Application-support directory for Ycode (ported from Legacy's `PathTool`;
/// Legacy's directory was `SwiftCode`, this one is `Ycode`).

public enum PathTool {
    public static func appSupportDirectory() throws -> URL {
        // SAFETY: applicationSupportDirectory is always present on macOS.
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupport = url.appendingPathComponent("Ycode", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }
}
