import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "PreviewManager")

/// The primary MainActor state coordinator that manages live SwiftUI Previews, discovery lists, and configuration parameters.
@Observable
@MainActor
public final class PreviewManager {
    public static let shared = PreviewManager()

    public var discoveredPreviews: [DiscoveredPreview] = []
    public var selectedPreviewID: String?
    public var activeSession: PreviewSession?
    public var isCompiling = false
    public var logStream: [String] = []

    // Configurations
    public var configuration = PreviewConfiguration()

    private init() {}

    public var selectedPreview: DiscoveredPreview? {
        discoveredPreviews.first { $0.id == selectedPreviewID }
    }

    /// Scans a workspace file and updates the list of discovered previews.
    public func scanFile(url: URL) async {
        logger.info("Scanning file for previews: \(url.lastPathComponent, privacy: .public)")
        let found = await PreviewDiscoveryService.shared.discoverPreviews(in: url)

        self.discoveredPreviews = found
        if selectedPreviewID == nil, let first = found.first {
            selectedPreviewID = first.id
        }

        // If there are discovered previews and no active session, start one automatically
        if let first = found.first {
            await startSession(for: first)
        }
    }

    /// Starts a compilation and live rendering session for a given discovered target.
    public func startSession(for preview: DiscoveredPreview) async {
        isCompiling = true
        logStream = ["Initializing preview environment..."]

        // Clean up previous active session
        await stopSession()

        do {
            let session = try await PreviewEngine.shared.startSession(
                for: preview.fileURL,
                projectDirectory: preview.fileURL.deletingLastPathComponent(),
                logHandler: { [weak self] message in
                    Task { @MainActor in
                        self?.logStream.append(message)
                    }
                }
            )

            self.activeSession = session
            logger.info("SwiftUI Preview session is active for \(preview.id, privacy: .public)")
            isCompiling = false
        } catch {
            let previewError: PreviewError = {
                if let err = error as? PreviewError {
                    return err
                }
                return .custom(error.localizedDescription)
            }()

            self.activeSession = PreviewSession(
                targetFileURL: preview.fileURL,
                status: .failed,
                logs: logStream,
                error: previewError,
                frameCount: 0,
                compileDuration: nil,
                lastRefreshed: Date()
            )

            logger.error("SwiftUI Preview session failed: \(error.localizedDescription, privacy: .public)")
            isCompiling = false
        }
    }

    /// Stops the current preview session.
    public func stopSession() async {
        if activeSession != nil {
            await PreviewEngine.shared.stopSession()
            activeSession = nil
        }
    }

    /// Re-compiles/reloads the active preview session.
    public func triggerReload() async {
        guard let preview = selectedPreview else { return }
        await startSession(for: preview)
    }

    /// Updates the target orientation or appearance configuration.
    public func updateConfiguration(_ config: PreviewConfiguration) async {
        self.configuration = config
        try? await PreviewCommunicationService.shared.sendConfiguration(config)
    }
}
