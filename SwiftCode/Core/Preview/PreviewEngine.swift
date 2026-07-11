import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "PreviewEngine")

/// Coordinates compilation, live reload triggers, and IPC streams.
public actor PreviewEngine: Sendable {
    public static let shared = PreviewEngine()
    private init() {}

    /// Runs scanning, validation, and triggers compilation for a selected file.
    public func startSession(
        for fileURL: URL,
        projectDirectory: URL,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> PreviewSession {
        logger.info("Initializing Preview Session for \(fileURL.lastPathComponent, privacy: .public)...")

        logHandler("Scanning workspace for target symbols...")
        let analyzer = ProjectAnalyzer()
        let analysis = await MainActor.run {
            analyzer.analyze(projectDirectory: projectDirectory)
        }

        guard !analysis.swiftFiles.isEmpty else {
            throw PreviewError.targetUnresolved(reason: "No Swift source files found in workspace.")
        }

        let compileDuration = try await PreviewBuildService.shared.compilePreview(
            for: fileURL,
            projectDirectory: projectDirectory,
            onLog: logHandler
        )

        logHandler("Establishing Inter-Process connection...")
        await PreviewCommunicationService.shared.startListening()

        _ = try? await PreviewHostManager.shared.launchPreviewHost(for: fileURL.path)

        return PreviewSession(
            targetFileURL: fileURL,
            status: .running,
            logs: ["Session started successfully."],
            error: nil,
            frameCount: 1,
            compileDuration: compileDuration,
            lastRefreshed: Date()
        )
    }

    /// Stops session and releases resources.
    public func stopSession() async {
        logger.info("Stopping current Preview Session.")
        await PreviewHostManager.shared.terminateActiveHost()
        await PreviewCommunicationService.shared.stopListening()
    }
}
