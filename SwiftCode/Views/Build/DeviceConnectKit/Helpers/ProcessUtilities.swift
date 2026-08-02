import Foundation

public struct ProcessUtilities {
    public static func findExecutable(name: String) -> URL? {
        let paths = ["/usr/bin", "/usr/local/bin", "/usr/sbin", "/bin", "/sbin", "/Library/Apple/usr/bin"]
        let fm = FileManager.default

        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    public static func cleanEnv() -> [String: String] {
        var baseEnv = ProcessInfo.processInfo.environment
        baseEnv.removeValue(forKey: "SWIFT_UPSTREAM_BUILD")
        return baseEnv
    }
}
