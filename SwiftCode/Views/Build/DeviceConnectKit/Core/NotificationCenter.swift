import Foundation

public final class DeviceConnectNotificationCenter: Sendable {
    public static let shared = DeviceConnectNotificationCenter()

    private init() {}

    public static let deviceConnected = Notification.Name("com.swiftcode.deviceconnect.connected")
    public static let deviceDisconnected = Notification.Name("com.swiftcode.deviceconnect.disconnected")
    public static let pipelineStateChanged = Notification.Name("com.swiftcode.deviceconnect.pipelineStateChanged")

    public func post(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: name, object: object, userInfo: userInfo)
    }
}
