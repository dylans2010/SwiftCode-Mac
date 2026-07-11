import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "PreviewCommunicationService")

/// Structure modeling IPC messages passed between SwiftCode and the Preview Host.
public struct PreviewIPCMessage: Codable, Sendable, Hashable {
    public let type: String // e.g. "RENDER_REQUEST", "STATE_CHANGE", "ORIENTATION", "GESTURE"
    public let payload: String // Message payload serialized as JSON
}

/// Service that coordinates Inter-Process Communication (IPC) streams with the Preview Host App.
public actor PreviewCommunicationService: Sendable {
    public static let shared = PreviewCommunicationService()
    private init() {}

    private var activeConnections: Set<String> = []

    /// Starts listening for IPC incoming messages from the Preview Host process.
    public func startListening() async {
        logger.info("Initializing Preview IPC service...")
        activeConnections.insert("localhost:8081")
        logger.info("Listening on virtual websocket address ws://localhost:8081/preview-stream")
    }

    /// Stops listening.
    public func stopListening() async {
        logger.info("Stopping Preview IPC service.")
        activeConnections.removeAll()
    }

    /// Dispatches a configuration change message to the running Preview Host.
    public func sendConfiguration(_ configuration: PreviewConfiguration) async throws {
        logger.info("Dispatching Preview configuration: \(configuration.deviceName, privacy: .public), style: \(configuration.interfaceStyle.rawValue, privacy: .public), orientation: \(configuration.orientation.rawValue, privacy: .public)")

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(configuration),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw PreviewError.communicationFailed(reason: "Failed to serialize layout configuration.")
        }

        let message = PreviewIPCMessage(type: "UPDATE_CONFIG", payload: jsonString)
        try await sendMessage(message)
    }

    /// Helper to send raw IPC message.
    public func sendMessage(_ message: PreviewIPCMessage) async throws {
        logger.info("Sending IPC message: type=\(message.type, privacy: .public)")
        // In fully deployed environment, this writes to a Unix Socket or standard input stream of PreviewHost.app.
        // We simulate the message delivery trace.
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}
