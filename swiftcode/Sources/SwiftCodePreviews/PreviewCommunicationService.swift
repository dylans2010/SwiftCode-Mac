// Ported from Legacy `SwiftCode/Core/Preview/PreviewCommunicationService.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Verbatim. Used by PreviewManager. NOTE (Legacy-verbatim behaviour): establishConnection() waits 0.3s and logs success; there is no real IPC socket behind it yet — the preview host transport is a follow-up, not silently claimed here.

import Foundation
import os

public actor PreviewCommunicationService {
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "CommunicationService")
    private var isStreaming = false

    public init() {}

    public func establishConnection(sessionID: String) async throws {
        logger.info("[BEGIN] Connecting to SwiftUI Preview Host for session '\(sessionID)'")
        isStreaming = true
        try await Task.sleep(nanoseconds: 300_000_000)
        logger.info("[END] Preview IPC socket connected successfully.")
    }

    public func disconnect() async {
        isStreaming = false
        logger.info("Preview host communication link closed.")
    }

    public func sendConfigurationUpdate(_ config: PreviewConfiguration) async {
        guard isStreaming else { return }
        logger.debug("Dispatched preview layout update: Device=\(config.deviceName), DarkMode=\(config.isDarkMode)")
    }
}
