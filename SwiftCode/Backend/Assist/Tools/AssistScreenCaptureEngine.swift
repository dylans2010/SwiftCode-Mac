import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "AssistScreenCapture")

public struct ScreenCaptureResult: Sendable {
    public let image: CGImage
    public let pngData: Data
    public let width: Int
    public let height: Int
    public let displayID: CGDirectDisplayID
    public let captureMode: String
}

public enum ScreenCaptureError: Error, LocalizedError {
    case permissionDenied(String)
    case displayNotFound(String)
    case captureFailed(String)
    case regionSelectionCancelled
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied(let msg):
            return "Screen Recording permission required: \(msg). Open System Settings > Privacy & Security > Screen Recording and allow SwiftCode."
        case .displayNotFound(let msg):
            return "Target display could not be located: \(msg)"
        case .captureFailed(let msg):
            return "Screen capture failed: \(msg)"
        case .regionSelectionCancelled:
            return "User cancelled region selection."
        case .encodingFailed:
            return "Failed to encode captured image as PNG."
        }
    }
}

public final class AssistScreenCaptureEngine: Sendable {
    public static let shared = AssistScreenCaptureEngine()

    private init() {}

    /// Checks whether SwiftCode has permission to capture the screen.
    public func checkAuthorization(promptIfDenied: Bool = false) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        if promptIfDenied {
            _ = CGRequestScreenCaptureAccess()
        }
        return false
    }

    /// Captures the full screen for the specified display (or main display if nil).
    public func captureFullScreen(displayID: CGDirectDisplayID? = nil, includeCursor: Bool = true) async throws -> ScreenCaptureResult {
        guard checkAuthorization(promptIfDenied: true) else {
            throw ScreenCaptureError.permissionDenied("Screen capture access is not authorized by the operating system.")
        }

        let targetDisplay = displayID ?? CGMainDisplayID()

        // Attempt ScreenCaptureKit screenshot on macOS 14+
        if #available(macOS 14.0, *) {
            do {
                let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if let scDisplay = shareableContent.displays.first(where: { $0.displayID == targetDisplay }) ?? shareableContent.displays.first {
                    let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    config.width = scDisplay.width * 2
                    config.height = scDisplay.height * 2
                    config.showsCursor = includeCursor
                    config.captureResolution = .best

                    let scImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    let pngData = try encodePNG(image: scImage)
                    return ScreenCaptureResult(
                        image: scImage,
                        pngData: pngData,
                        width: scImage.width,
                        height: scImage.height,
                        displayID: scDisplay.displayID,
                        captureMode: "fullscreen"
                    )
                }
            } catch {
                logger.warning("ScreenCaptureKit screenshot capture failed, falling back to CoreGraphics: \(error.localizedDescription)")
            }
        }

        // CoreGraphics fallback
        guard let cgImage = CGDisplayCreateImage(targetDisplay) else {
            throw ScreenCaptureError.captureFailed("CGDisplayCreateImage returned null for display \(targetDisplay).")
        }

        let pngData = try encodePNG(image: cgImage)
        return ScreenCaptureResult(
            image: cgImage,
            pngData: pngData,
            width: cgImage.width,
            height: cgImage.height,
            displayID: targetDisplay,
            captureMode: "fullscreen"
        )
    }

    /// Captures a user-selected screen region using an interactive native selection overlay.
    @MainActor
    public func captureUserSelectedRegion() async throws -> ScreenCaptureResult {
        guard checkAuthorization(promptIfDenied: true) else {
            throw ScreenCaptureError.permissionDenied("Screen capture access is not authorized by the operating system.")
        }

        let selectedRect = try await RegionSelectionOverlayWindow.presentSelection()
        guard selectedRect.width > 2 && selectedRect.height > 2 else {
            throw ScreenCaptureError.regionSelectionCancelled
        }

        // Convert Cocoa screen coordinates (origin bottom-left) to CoreGraphics coordinates (origin top-left of main display)
        let mainDisplayID = CGMainDisplayID()
        let mainDisplayHeight = CGFloat(CGDisplayPixelsHigh(mainDisplayID))
        let cgRect = CGRect(
            x: selectedRect.origin.x,
            y: mainDisplayHeight - selectedRect.origin.y - selectedRect.height,
            width: selectedRect.width,
            height: selectedRect.height
        )

        // Find which display contains this rect
        var targetDisplay = mainDisplayID
        var maxDisplayCount: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplayCount))
        if CGGetActiveDisplayList(maxDisplayCount, &activeDisplays, &maxDisplayCount) == .success {
            for i in 0..<Int(maxDisplayCount) {
                let disp = activeDisplays[i]
                let bounds = CGDisplayBounds(disp)
                if bounds.intersects(cgRect) {
                    targetDisplay = disp
                    break
                }
            }
        }

        guard let fullScreenImage = CGDisplayCreateImage(targetDisplay) else {
            throw ScreenCaptureError.captureFailed("Failed to capture display for region cropping.")
        }

        let dispBounds = CGDisplayBounds(targetDisplay)
        let scale = CGFloat(fullScreenImage.width) / dispBounds.width

        let cropRect = CGRect(
            x: (cgRect.origin.x - dispBounds.origin.x) * scale,
            y: (cgRect.origin.y - dispBounds.origin.y) * scale,
            width: cgRect.width * scale,
            height: cgRect.height * scale
        ).integral

        guard let cropped = fullScreenImage.cropping(to: cropRect) else {
            // Fallback to full screen if crop fails
            let png = try encodePNG(image: fullScreenImage)
            return ScreenCaptureResult(
                image: fullScreenImage,
                pngData: png,
                width: fullScreenImage.width,
                height: fullScreenImage.height,
                displayID: targetDisplay,
                captureMode: "region_fallback"
            )
        }

        let pngData = try encodePNG(image: cropped)
        return ScreenCaptureResult(
            image: cropped,
            pngData: pngData,
            width: cropped.width,
            height: cropped.height,
            displayID: targetDisplay,
            captureMode: "region"
        )
    }

    /// Encodes a CGImage to PNG Data.
    public func encodePNG(image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenCaptureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.encodingFailed
        }
        return data as Data
    }
}

// MARK: - Native Interactive Region Selection Overlay

@MainActor
private final class RegionSelectionOverlayWindow: NSWindow {
    private var completion: ((Result<NSRect, Error>) -> Void)?

    static func presentSelection() async throws -> NSRect {
        try await withCheckedThrowingContinuation { continuation in
            let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
            let window = RegionSelectionOverlayWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.25)
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true

            let overlayView = RegionSelectionOverlayView(frame: NSRect(origin: .zero, size: frame.size))
            window.contentView = overlayView

            window.completion = { result in
                window.orderOut(nil)
                continuation.resume(with: result)
            }

            overlayView.parentWindow = window
            window.makeKeyAndOrderFront(nil)
            NSCursor.crosshair.push()
        }
    }

    fileprivate func finishWithRect(_ rect: NSRect) {
        NSCursor.pop()
        completion?(.success(rect))
        completion = nil
    }

    fileprivate func cancelSelection() {
        NSCursor.pop()
        completion?(.failure(ScreenCaptureError.regionSelectionCancelled))
        completion = nil
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            cancelSelection()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
private final class RegionSelectionOverlayView: NSView {
    weak var parentWindow: RegionSelectionOverlayWindow?
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let start = startPoint, let current = currentPoint else { return }

        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )

        // Clear out selected area
        NSGraphicsContext.saveGraphicsState()
        NSColor.clear.setFill()
        rect.fill(using: .copy)

        // Border and highlight
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2.0
        path.stroke()

        // Size badge
        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7)
        ]
        let badgeRect = NSRect(x: rect.origin.x, y: max(0, rect.origin.y - 20), width: 80, height: 18)
        (sizeText as NSString).draw(in: badgeRect, withAttributes: attrs)

        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else {
            parentWindow?.cancelSelection()
            return
        }
        let current = event.locationInWindow
        let selectedRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        if selectedRect.width > 5 && selectedRect.height > 5 {
            parentWindow?.finishWithRect(selectedRect)
        } else {
            parentWindow?.cancelSelection()
        }
    }
}
