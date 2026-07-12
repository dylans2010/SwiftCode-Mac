import Foundation
import os

public actor PreviewEngine {
    private let discoveryService = PreviewDiscoveryService()
    private let buildService = PreviewBuildService()
    private let hostManager = PreviewHostManager()
    private let communicationService = PreviewCommunicationService()
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "PreviewEngine")

    public init() {}

    public func runPreviewSession(
        sourceFilePath: String,
        sourceCode: String,
        targetView: String,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> PreviewSession {
        logger.info("[BEGIN] Initiating SwiftUI preview session for target '\(targetView)'")
        let startTime = Date()

        logHandler("Analyzing source structure...")
        let previews = await discoveryService.discoverPreviews(inSourceCode: sourceCode)

        let actualTarget = previews.first(where: { $0 == targetView }) ?? previews.first ?? targetView
        logHandler("Discovered target preview block: '\(actualTarget)'")

        let sessionID = UUID().uuidString

        do {
            logHandler("Compiling view module...")
            let dylibURL = try await buildService.compilePreview(sourcePath: sourceFilePath, targetName: actualTarget, outputHandler: logHandler)

            logHandler("Launching SwiftUI rendering viewport...")
            _ = try await hostManager.launchHostApp(bundleURL: dylibURL, deviceUDID: "E79A17A8-8F6E-4E6E-8041-3F6ECBB23214")

            logHandler("Connecting preview socket stream...")
            try await communicationService.establishConnection(sessionID: sessionID)

            let duration = Date().timeIntervalSince(startTime)
            logger.info("[END] Preview session \(sessionID) is fully live in \(duration)s")
            logHandler("Preview fully loaded.")

            return PreviewSession(
                sessionID: sessionID,
                sourceFilePath: sourceFilePath,
                targetViewName: actualTarget,
                lastCompiledAt: Date(),
                status: "Ready"
            )
        } catch {
            logger.error("[FAILED] Preview session start failed: \(error.localizedDescription)")
            logHandler("Preview failed to compile: \(error.localizedDescription)")
            throw error
        }
    }

    public func stopPreviewSession() async {
        logger.info("Stopping active preview session...")
        await hostManager.terminateActiveHost()
        await communicationService.disconnect()
    }
}
