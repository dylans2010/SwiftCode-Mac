// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistScreenCaptureEngine.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/AssistScreenCaptureEngine.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Interactive region-selection overlay (RegionSelectionOverlayView/Window): user drags to pick a region on screen
// ADAPTATIONS:
//   - macOS-only file (destination convention, cf. SwiftCodeTools+Screenshot.swift): Apple-framework imports wrapped in #if canImport(...); whole body guarded by #if canImport(AppKit) && canImport(ScreenCaptureKit) — on Linux the file contributes nothing and take_screenshot keeps its honest failure path.
// UNRESOLVED DEPENDENCIES: none found by static scan (SwiftUI/Foundation/Apple-framework names excluded).
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+Screenshot.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import os


#if canImport(AppKit) && canImport(ScreenCaptureKit)
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

        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = shareableContent.displays.first(where: { $0.displayID == targetDisplay }) ?? shareableContent.displays.first else {
            throw ScreenCaptureError.displayNotFound("Target display \(targetDisplay) was not found in shareable displays.")
        }

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

        let fullScreenResult = try await captureFullScreen(displayID: targetDisplay, includeCursor: false)
        let fullScreenImage = fullScreenResult.image
        let dispBounds = CGDisplayBounds(targetDisplay)
        let scale = CGFloat(fullScreenImage.width) / dispBounds.width

        let cropRect = CGRect(
            x: (cgRect.origin.x - dispBounds.origin.x) * scale,
            y: (cgRect.origin.y - dispBounds.origin.y) * scale,
            width: cgRect.width * scale,
            height: cgRect.height * scale
        ).integral

        guard let cropped = fullScreenImage.cropping(to: cropRect) else {
            return ScreenCaptureResult(
                image: fullScreenImage,
                pngData: fullScreenResult.pngData,
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

#endif
