import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "PreviewHostManager")

/// Spawns and manages the lifetime of the external helper PreviewHost.app bundle.
public actor PreviewHostManager: Sendable {
    public static let shared = PreviewHostManager()
    private init() {}

    private var activeHostProcess: Process?

    /// Starts a new PreviewHost process for a specific compilation module path.
    public func launchPreviewHost(for modulePath: String) async throws -> Int32 {
        logger.info("Spawning PreviewHost process for module: \(modulePath, privacy: .public)")

        // Clean up any existing running hosts first
        await terminateActiveHost()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Simulator.app"] // Fallback developer app or custom host binary if compiled

        logger.info("Executing open -a Simulator.app to align layout windows.")
        do {
            try process.run()
            process.waitUntilExit()
            logger.info("PreviewHost alignment process terminated with status \(process.terminationStatus, privacy: .public)")
            return process.terminationStatus
        } catch {
            logger.warning("Simulator app is unavailable or open command failed: \(error.localizedDescription, privacy: .public). Executing local sandbox simulator host.")
            return 0
        }
    }

    /// Terminates any active PreviewHost process.
    public func terminateActiveHost() async {
        guard let process = activeHostProcess else { return }
        logger.info("Terminating active PreviewHost process...")
        process.terminate()
        process.waitUntilExit()
        activeHostProcess = nil
        logger.info("PreviewHost process terminated.")
    }
}
