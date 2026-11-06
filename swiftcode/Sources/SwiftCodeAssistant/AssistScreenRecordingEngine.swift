import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistScreenRecording")

public struct ScreenRecordResult: Sendable {
    public let fileURL: URL
    public let data: Data
    public let duration: TimeInterval
    public let width: Int
    public let height: Int
    public let appBundleID: String
    public let appName: String
    public let outputFormat: String
}

public enum ScreenRecordError: Error, LocalizedError {
    case permissionDenied(String)
    case appNotFound(String)
    case noEligibleWindows(String)
    case recordingAlreadyInProgress
    case initializationFailed(String)
    case recordingFailed(String)
    case invalidDuration(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let msg):
            return "Screen Recording permission required: \(msg). Grant Screen Recording in macOS System Settings > Privacy & Security > Screen Recording."
        case .appNotFound(let id):
            return "Application '\(id)' could not be found or is not currently running. Please launch the application or verify its bundle identifier."
        case .noEligibleWindows(let app):
            return "No on-screen capture-eligible windows were found for application '\(app)'."
        case .recordingAlreadyInProgress:
            return "Another screen recording is currently in progress. Concurrent screen recordings are prevented for resource safety."
        case .initializationFailed(let msg):
            return "Failed to initialize screen recording engine: \(msg)"
        case .recordingFailed(let msg):
            return "Screen recording failed: \(msg)"
        case .invalidDuration(let msg):
            return "Invalid recording duration: \(msg). Duration must be between 1 and 60 seconds."
        }
    }
}

public actor AssistScreenRecordingEngine {
    public static let shared = AssistScreenRecordingEngine()

    private var isRecording = false

    private init() {}

    /// Resolves an application identifier (bundle ID or app name) to a running application.
    public func resolveApplication(identifier: String) -> NSRunningApplication? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let runningApps = NSWorkspace.shared.runningApplications

        // 1. Exact match on bundle identifier
        if let app = runningApps.first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return app
        }

        // 2. Exact match on localized name
        if let app = runningApps.first(where: { $0.localizedName?.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return app
        }

        // 3. Substring match on bundle identifier or localized name
        if let app = runningApps.first(where: {
            ($0.bundleIdentifier?.localizedCaseInsensitiveContains(trimmed) == true) ||
            ($0.localizedName?.localizedCaseInsensitiveContains(trimmed) == true)
        }) {
            return app
        }

        return nil
    }

    /// Records the screen of the target application for the specified duration.
    public func recordApplication(
        appIdentifier: String,
        durationSeconds: TimeInterval = 10,
        captureMode: String = "window",
        includeAudio: Bool = false,
        outputFormat: String = "mov"
    ) async throws -> ScreenRecordResult {
        guard durationSeconds >= 1 && durationSeconds <= 60 else {
            throw ScreenRecordError.invalidDuration("\(durationSeconds) seconds requested")
        }

        guard !isRecording else {
            throw ScreenRecordError.recordingAlreadyInProgress
        }

        guard AssistScreenCaptureEngine.shared.checkAuthorization(promptIfDenied: true) else {
            throw ScreenRecordError.permissionDenied("Screen capture access is not authorized by the operating system.")
        }

        guard let targetApp = resolveApplication(identifier: appIdentifier) else {
            throw ScreenRecordError.appNotFound(appIdentifier)
        }

        let bundleID = targetApp.bundleIdentifier ?? appIdentifier
        let appName = targetApp.localizedName ?? appIdentifier

        isRecording = true
        defer { isRecording = false }

        // Find shareable content & window for the target application
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let appWindows = shareableContent.windows.filter { window in
            guard let owningApp = window.owningApplication else { return false }
            return owningApp.processID == targetApp.processIdentifier && window.isOnScreen && window.frame.width > 20 && window.frame.height > 20
        }

        guard let targetWindow = appWindows.first else {
            throw ScreenRecordError.noEligibleWindows("\(appName) (PID: \(targetApp.processIdentifier))")
        }

        let tempDir = FileManager.default.temporaryDirectory
        let recordingID = UUID().uuidString
        let tempFileURL = tempDir.appendingPathComponent("screenrecord_\(recordingID).\(outputFormat)")

        let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
        let config = SCStreamConfiguration()
        let captureWidth = max(320, Int(targetWindow.frame.width) * 2)
        let captureHeight = max(240, Int(targetWindow.frame.height) * 2)
        // Dimensions must be even for video encoders
        let normalizedWidth = (captureWidth / 2) * 2
        let normalizedHeight = (captureHeight / 2) * 2

        config.width = normalizedWidth
        config.height = normalizedHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = includeAudio

        let session = StreamRecorderSession(
            outputURL: tempFileURL,
            width: normalizedWidth,
            height: normalizedHeight,
            outputFormat: outputFormat
        )

        try session.start()

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: session.recordingQueue)
        try await stream.startCapture()

        // Wait for requested duration
        try await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))

        do {
            try await stream.stopCapture()
        } catch {
            logger.warning("Error stopping SCStream capture: \(error.localizedDescription)")
        }

        try await session.finish()

        let fileData = (try? Data(contentsOf: tempFileURL)) ?? Data()
        try? FileManager.default.removeItem(at: tempFileURL)

        guard !fileData.isEmpty else {
            throw ScreenRecordError.recordingFailed("Recorded media container was empty or failed to finalize.")
        }

        return ScreenRecordResult(
            fileURL: tempFileURL,
            data: fileData,
            duration: durationSeconds,
            width: normalizedWidth,
            height: normalizedHeight,
            appBundleID: bundleID,
            appName: appName,
            outputFormat: outputFormat
        )
    }
}

// MARK: - Internal Session & SCStreamOutput Handler

private final class StreamRecorderSession: NSObject, SCStreamOutput, @unchecked Sendable {
    let outputURL: URL
    let width: Int
    let height: Int
    let outputFormat: String
    let recordingQueue = DispatchQueue(label: "com.swiftcode.assist.screenrecord", qos: .userInitiated)

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var isStarted = false
    private var frameCount = 0

    init(outputURL: URL, width: Int, height: Int, outputFormat: String) {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.outputFormat = outputFormat
        super.init()
    }

    func start() throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let containerType: AVFileType = outputFormat.lowercased() == "mp4" ? .mp4 : .mov
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: containerType)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        if writer.canAdd(input) {
            writer.add(input)
        } else {
            throw ScreenRecordError.initializationFailed("AVAssetWriter cannot add video input.")
        }

        self.assetWriter = writer
        self.videoInput = input
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        recordingQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  let input = self.videoInput else { return }

            if !self.isStarted {
                let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startWriting()
                writer.startSession(atSourceTime: startTime)
                self.isStarted = true
            }

            if writer.status == .writing && input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
                self.frameCount += 1
            }
        }
    }

    func finish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recordingQueue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter, let input = self.videoInput else {
                    continuation.resume()
                    return
                }

                input.markAsFinished()
                if writer.status == .writing {
                    writer.finishWriting {
                        if let error = writer.error {
                            continuation.resume(throwing: ScreenRecordError.recordingFailed(error.localizedDescription))
                        } else {
                            continuation.resume()
                        }
                    }
                } else if writer.status == .failed, let error = writer.error {
                    continuation.resume(throwing: ScreenRecordError.recordingFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
