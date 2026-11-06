import Foundation
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The real screen-recording engine for `take_screenrecord`:
/// Legacy's `AssistScreenRecordingEngine` (`StreamRecorderSession`)
/// ported to ScreenCaptureKit + AVAssetWriter.
///
/// * One recording at a time (the host holds the active session;
///   a second call while one runs fails naming the first).
/// * Video only: `include_audio` sets `capturesAudio` on the
///   stream configuration, but no audio input is wired — exactly
///   Legacy's behaviour, and never claimed otherwise.
/// * `capture_mode: "window"` (the default) records the app's
///   first on-screen window larger than 20×20 points; Legacy
///   accepted `capture_mode` but always used the window filter, so
///   `"application_display"` is a recorded deviation: it records
///   the whole display that window is on.
/// * H.264, 2× the window/display size with even dimensions,
///   30 fps, cursor shown.
/// * Linux (and any build without ScreenCaptureKit/AVFoundation)
///   keeps the exact honest failure.
///
/// See `specs/ide/gap-closure-failing-tools.md` §3.
extension SwiftCodeMCPHost {
    /// `take_screenrecord`: resolves the app, records it for the
    /// requested duration, and saves the artifact.
    func takeScreenrecordReal(_ call: MCPToolCall) async throws -> MCPToolResult {
        // Argument validation runs on every platform (the tests
        // assert these errors on Linux too); only the capture
        // itself is macOS-only.
        guard let rawAppId = call.arguments["app_identifier"]?.string,
              !rawAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPToolError("Missing required parameter 'app_identifier'. Provide a bundle identifier or application name.")
        }
        let durationSeconds = call.arguments["recording_duration"]?.double ?? 10.0
        guard durationSeconds >= 1 && durationSeconds <= 60 else {
            throw MCPToolError("Requested recording duration (\(durationSeconds)s) is invalid. Duration must be between 1 and 60 seconds.")
        }
        let format = (call.string("output_format") ?? "mov").lowercased()
        guard format == "mov" || format == "mp4" else {
            throw MCPToolError("Unsupported output_format '\(format)'. Supported: 'mov', 'mp4'.")
        }
#if canImport(ScreenCaptureKit) && canImport(AVFoundation) && canImport(AppKit)
        let s = try session(for: call)
        let appIdentifier = rawAppId.trimmingCharacters(in: .whitespacesAndNewlines)
        let captureMode = (call.string("capture_mode") ?? "window").lowercased()
        let includeAudio = call.bool("include_audio") ?? false
        guard screenRecordingSession == nil else {
            throw MCPToolError("A screen recording is already in progress. Wait for it to finish before starting another.")
        }
        guard terminalScreenCaptureAuthorized() else {
            throw MCPToolError("Screen Recording permission has not been granted. Please grant Screen Recording permission to SwiftCode in macOS System Settings > Privacy & Security > Screen Recording, then retry.")
        }
        guard let app = terminalResolveRunningApplication(appIdentifier) else {
            throw MCPToolError("Application '\(appIdentifier)' is not running.")
        }
        let appName = app.localizedName ?? appIdentifier
        let bundleID = app.bundleIdentifier ?? appIdentifier
        let pid = app.processIdentifier
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.frame.width > 20 && $0.frame.height > 20
        }) else {
            throw MCPToolError("Application '\(appName)' has no on-screen window larger than 20×20 points to record.")
        }
        let (filter, width, height): (SCContentFilter, Int, Int)
        if captureMode == "application_display" {
            guard let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first else {
                throw MCPToolError("No display found for application '\(appName)'.")
            }
            filter = SCContentFilter(display: display, excludingWindows: [])
            width = ScreenRecordingSession.even(Int(display.width) * 2)
            height = ScreenRecordingSession.even(Int(display.height) * 2)
        } else {
            filter = SCContentFilter(desktopIndependentWindow: window)
            width = ScreenRecordingSession.even(Int(window.frame.width) * 2)
            height = ScreenRecordingSession.even(Int(window.frame.height) * 2)
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let safeName = appName.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24)
        let fileName = "screenrecord_\(safeName)_\(timestamp).\(format)"
        let rel = ".assist_temp/artifacts/\(fileName)"
        let url = artifactDirectory(in: s).appendingPathComponent(fileName)
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: nil,
                                           summary: "Save screen recording artifact \(rel) (\(width)x\(height), \(format))", call: call)
        let session = try ScreenRecordingSession(filter: filter, width: width, height: height,
                                                 format: format, includeAudio: includeAudio, outputURL: url)
        screenRecordingSession = session
        defer { screenRecordingSession = nil }
        do {
            try FileManager.default.createDirectory(at: artifactDirectory(in: s), withIntermediateDirectories: true)
            try await session.start()
            try await Task.sleep(for: .seconds(durationSeconds))
            let recorded = try await session.stop()
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            var index = loadFileReadingArtifactIndex(in: s)
            let entry = FileReadingArtifactIndexEntry(id: UUID(), description: "Screen recording of \(appName) (\(recorded.duration)s)",
                                                     kind: "video", createdAt: Date(), sourceMessageID: nil)
            index[fileName] = entry
            saveFileReadingArtifactIndex(index, in: s)
            noteFileWritingChanged(url, in: s)
            return .structured(["path": .string(rel), "duration": .double(recorded.duration),
                                "width": .int(width), "height": .int(height),
                                "app_identifier": .string(bundleID), "app_name": .string(appName),
                                "artifact_id": .string(entry.id.uuidString), "format": .string(format),
                                "size_bytes": .int(size)],
                               summary: "Recorded \(appName) for \(String(format: "%.1f", recorded.duration))s (\(width)×\(height), \(format)). Artifact saved to '\(rel)'.")
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw MCPToolError("Screen recording of '\(appName)' failed: \(error.localizedDescription)")
        }
#else
        throw MCPToolError("take_screenrecord needs a ScreenCaptureKit stream-recording engine (SCStream + video writer), which is only available on macOS; no recording was made. Recording also requires Screen Recording permission in macOS System Settings > Privacy & Security > Screen Recording.")
#endif
    }
}

#if canImport(ScreenCaptureKit) && canImport(AVFoundation)
extension SwiftCodeMCPHost {
    /// The recording currently in progress, if any.
    var screenRecordingSession: ScreenRecordingSession? {
        get { sharedScreenRecordingBox.value }
        set { sharedScreenRecordingBox.value = newValue }
    }
}

/// One in-progress ScreenCaptureKit recording: an `SCStream`
/// feeding an `AVAssetWriter` (H.264, video only).
final class ScreenRecordingSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let outputURL: URL
    let width: Int
    let height: Int
    private var stream: SCStream!
    private let writer: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    private let queue = DispatchQueue(label: "swiftcode.screen-recording")
    private let lock = NSLock()
    private var sessionStarted = false
    private var firstPTS: CMTime?
    private var lastPTS: CMTime?
    private var streamError: Error?
    private var frameCount = 0

    init(filter: SCContentFilter, width: Int, height: Int, format: String, includeAudio: Bool, outputURL: URL) throws {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.showsCursor = true
        config.captureResolution = .best
        config.capturesAudio = includeAudio
        let fileType: AVFileType = format == "mp4" ? .mp4 : .mov
        self.writer = try AVAssetWriter(url: outputURL, fileType: fileType)
        self.writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        writerInput.expectsMediaDataInRealTime = true
        super.init()
        self.stream = SCStream(filter: filter, configuration: config, delegate: self)
        guard writer.canAdd(writerInput) else {
            throw MCPToolError("Could not add a video input to the recording writer.")
        }
        writer.add(writerInput)
    }

    /// Rounds a dimension down to the nearest even number (H.264
    /// requires even dimensions — Legacy's `StreamRecorderSession`
    /// rule).
    static func even(_ value: Int) -> Int { max(2, value - (value % 2)) }

    func start() async throws {
        guard writer.startWriting() else {
            throw MCPToolError("Could not start the recording writer: \(writer.error?.localizedDescription ?? "unknown error")")
        }
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
    }

    /// Stops the stream and finishes the file. Returns the recorded
    /// duration in seconds (first to last video frame) and the
    /// frame count.
    func stop() async throws -> (duration: Double, frameCount: Int) {
        try await stream.stopCapture()
        writerInput.markAsFinished()
        let frames = lock.withLock { frameCount }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = self.writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        let (first, last) = lock.withLock { (firstPTS, lastPTS) }
        let duration: Double
        if let first, let last, last > first {
            duration = CMTimeGetSeconds(CMTimeSubtract(last, first))
        } else {
            duration = 0
        }
        if let error = lock.withLock({ streamError }) { throw error }
        return (duration, frames)
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        lock.lock()
        if !sessionStarted {
            sessionStarted = true
            firstPTS = pts
            writer.startSession(atSourceTime: pts)
        }
        lastPTS = pts
        frameCount += 1
        lock.unlock()
        guard writerInput.isReadyForMoreMediaData else { return }
        writerInput.append(sampleBuffer)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        streamError = error
        lock.unlock()
    }
}

/// The host's active recording, kept in a tiny box so the
/// extension can hold it without changing `SwiftCodeMCPHost`'s
/// stored properties (shared file — coordinator-owned).
final class ScreenRecordingSessionsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: ScreenRecordingSession?
    var value: ScreenRecordingSession? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

private let sharedScreenRecordingBox = ScreenRecordingSessionsBox()
#endif
