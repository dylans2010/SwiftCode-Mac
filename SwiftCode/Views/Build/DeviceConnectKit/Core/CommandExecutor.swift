import Foundation
import OSLog

public actor CommandExecutor {
    public static let shared = CommandExecutor()
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "CommandExecutor")

    private var activeCommands: [UUID: Process] = [:]

    private init() {}

    public func registerActiveProcess(_ process: Process) -> UUID {
        let id = UUID()
        activeCommands[id] = process
        return id
    }

    public func terminateProcess(id: UUID) {
        if let proc = activeCommands[id] {
            if proc.isRunning {
                proc.terminate()
            }
            activeCommands.removeValue(forKey: id)
            Self.logger.info("Process \(id) terminated successfully.")
        }
    }

    public func terminateAll() {
        for id in activeCommands.keys {
            terminateProcess(id: id)
        }
    }
}
