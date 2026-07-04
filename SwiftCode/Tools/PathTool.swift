import Foundation

public enum PathTool {
    public static func appSupportDirectory() throws -> URL {
        // SAFETY: applicationSupportDirectory is always present on macOS.
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupport = url.appendingPathComponent("SwiftCode", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }
}
