import Foundation
import os

public actor SimulatorInstallationService {
    private let simctlService = SimctlService()
    private let logger = Logger(subsystem: "com.swiftcode.simulator", category: "InstallationService")

    public init() {}

    public func installApp(at path: String, onDeviceUDID udid: String) async throws {
        logger.info("[BEGIN] Installing application package from '\(path)' on simulator '\(udid)'")
        let startTime = Date()

        // Validate path format
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            throw SimulatorError.invalidApplicationBundle(path: path, reason: "The package file does not exist at the specified path.")
        }

        let isAppBundle = path.hasSuffix(".app")
        let isIpaBundle = path.hasSuffix(".ipa")

        guard isAppBundle || isIpaBundle else {
            throw SimulatorError.invalidApplicationBundle(path: path, reason: "The specified target is not a valid simulator application (.app) or archive (.ipa) bundle.")
        }

        do {
            try await simctlService.installApplication(udid: udid, appPath: path)
            let duration = Date().timeIntervalSince(startTime)
            logger.info("[END] Application installed successfully in \(duration)s")
        } catch {
            logger.error("[FAILED] Application installation failed: \(error.localizedDescription)")
            throw error
        }
    }
}
