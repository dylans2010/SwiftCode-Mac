import Foundation

public enum IDEProcess {
    public static let isTestProcess: Bool = {
        let name = ProcessInfo.processInfo.processName
        return name.contains("xctest") || name.contains("swiftpm-testing-helper") || name.hasSuffix("PackageTests")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }()

    public static let willTerminateNotification = Notification.Name("NSApplicationWillTerminateNotification")
}
