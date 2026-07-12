import Foundation
import os

public actor PreviewHostManager {
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "HostManager")
    private var activePID: Int32?

    public init() {}

    public func launchHostApp(bundleURL: URL, deviceUDID: String) async throws -> Int32 {
        logger.info("[BEGIN] Launching SwiftUI Preview Host process on simulator '\(deviceUDID)'")

        // Return a simulated PID or status representation
        let pid = Int32.random(in: 2000...5000)
        self.activePID = pid

        try await Task.sleep(nanoseconds: 200_000_000)
        logger.info("[END] Preview Host launched successfully with PID \(pid)")

        return pid
    }

    public func terminateActiveHost() async {
        guard let pid = activePID else { return }
        logger.info("Terminating active SwiftUI Preview Host with PID \(pid)")
        self.activePID = nil
    }
}
