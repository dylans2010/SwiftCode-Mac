import Foundation
import OSLog

public final class DeviceConnectEngine: Sendable {
    public static let shared = DeviceConnectEngine()
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DeviceConnectEngine")

    private let discovery = DeviceDiscovery()
    private let pipeline = DeploymentPipeline()
    private let validator = EnvironmentValidator()

    private init() {}

    public func startDiscovery(onDiscover: @escaping @Sendable ([ConnectedDevice]) -> Void) async {
        await discovery.startContinuousDiscovery(interval: 10, onDiscover: onDiscover)
    }

    public func stopDiscovery() async {
        await discovery.stopContinuousDiscovery()
    }

    public func validate() async -> (environment: DeviceEnvironment, diagnostics: [String]) {
        return await validator.validate()
    }

    public func deploy(
        device: ConnectedDevice,
        projectName: String,
        projectPath: String,
        scheme: String,
        appBundleURL: URL,
        bundleIdentifier: String,
        onStateUpdate: @escaping @Sendable (DeploymentStatus, String) -> Void,
        onLogUpdate: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        return await pipeline.run(
            device: device,
            projectName: projectName,
            projectPath: projectPath,
            scheme: scheme,
            appBundleURL: appBundleURL,
            bundleIdentifier: bundleIdentifier,
            onStateUpdate: onStateUpdate,
            onLogUpdate: onLogUpdate
        )
    }
}
