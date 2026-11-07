import Foundation

#if canImport(UserNotifications)
import UserNotifications
#endif

public struct DeviceConnectBuildService: Sendable {
    public init() {}

    public func build(
        projectPath: String,
        scheme: String,
        configuration: String,
        destination: String,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        return try await BuildProjectCommand().execute(
            projectPath: projectPath,
            scheme: scheme,
            configuration: configuration,
            destination: destination,
            onLog: onLog
        )
    }
}

public struct DeviceConnectDeviceService: Sendable {
    public init() {}

    public func discover() async throws -> [ConnectedDevice] {
        return try await DiscoverDevicesCommand().execute()
    }
}

public struct DeviceConnectEnvironmentService: Sendable {
    public init() {}

    public func validate() async throws -> DeviceEnvironment {
        return try await ValidateEnvironmentCommand().execute()
    }
}

public struct DeviceConnectInstallService: Sendable {
    public init() {}

    public func install(
        deviceUDID: String,
        appBundleURL: URL,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        return try await InstallApplicationCommand().execute(
            deviceUDID: deviceUDID,
            appBundleURL: appBundleURL,
            onProgress: onProgress
        )
    }
}

public struct DeviceConnectLaunchService: Sendable {
    public init() {}

    public func launch(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Int32? {
        return try await LaunchApplicationCommand().execute(
            deviceUDID: deviceUDID,
            bundleIdentifier: bundleIdentifier
        )
    }
}

public struct DeviceConnectLogService: Sendable {
    public init() {}

    public func streamLogs(
        deviceUDID: String,
        pid: Int32,
        onLog: @escaping @Sendable (String) -> Void
    ) throws -> Process {
        return try RuntimeLogsCommand().execute(
            deviceUDID: deviceUDID,
            pid: pid,
            onLog: onLog
        )
    }
}

public final class DeviceConnectNotificationService: Sendable {
    public static let shared = DeviceConnectNotificationService()

    private init() {}

    public func postNotification(title: String, subtitle: String = "", body: String) {
#if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { _ in }
#else
#endif
    }
}

public struct DeviceConnectRuntimeService: Sendable {
    public init() {}

    public func stop(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Bool {
        return try await StopApplicationCommand().execute(
            deviceUDID: deviceUDID,
            bundleIdentifier: bundleIdentifier
        )
    }
}

public struct DeviceConnectSigningService: Sendable {
    public init() {}

    public func validateIdentities() async throws -> [String] {
        return try await SigningValidationCommand().execute()
    }
}
