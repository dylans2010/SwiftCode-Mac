import Foundation
import Observation

@Observable
@MainActor
public final class ConsoleManager {
    public static let shared = ConsoleManager()

    public private(set) var buildLogs: [DeviceLog] = []
    public private(set) var runtimeLogs: [DeviceLog] = []

    public var selectedConsoleTab: Int = 0 // 0: Build, 1: Runtime

    private init() {}

    public func appendLog(_ log: DeviceLog) {
        if log.type == .build {
            buildLogs.append(log)
        } else {
            runtimeLogs.append(log)
        }
    }

    public func clearLogs() {
        if selectedConsoleTab == 0 {
            buildLogs.removeAll()
        } else {
            runtimeLogs.removeAll()
        }
    }
}
