import Foundation
import os.log

@MainActor
public enum SDKBootstrap {

    private static var didBootstrap = false

    private static let logger = Logger(
        subsystem: "com.swiftcode.app",
        category: "SDKBootstrap"
    )

    public static func bootstrapIfNeeded() async {
        guard !didBootstrap else { return }
        do {
            logger.debug("SDKBootstrap: installing one-time host registrations")

            try await SDKViewOpener.shared.registerBuiltInOpeners()

            let summary = await SDKExtensionManager.shared.startAll()
            if !summary.started.isEmpty {
                logger.debug("SDKBootstrap: started \(summary.started.count, privacy: .public) extension(s)")
            }
            for skipped in summary.skipped {
                logger.debug("SDKBootstrap: skipped '\(skipped.id, privacy: .public)': \(skipped.reason, privacy: .public)")
            }
            for failed in summary.failed {
                logger.error("SDKBootstrap: failed to start '\(failed.id, privacy: .public)': \(failed.reason, privacy: .public)")
            }

            await SDKAssistUIOpener.registerAssistViewOpener()

            didBootstrap = true
            logger.debug("SDKBootstrap: complete")
        } catch {
            logger.error("SDKBootstrap failed: \(error.localizedDescription, privacy: .public)")
            logger.error("ui.openView will throw .serviceUnavailable until a later call succeeds.")
        }
    }
}
