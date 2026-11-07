import Foundation
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import YcodeAssistant
import YcodeIDECore

extension SwiftCodeMCPHost {
    func takeScreenshotReal(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let captureModeRaw = call.arguments["capture_mode"]?.string?.lowercased() ?? "fullscreen"
        let includeCursor = call.bool("include_cursor") ?? true
        let displayID = call.int("display_id").flatMap { $0 >= 0 ? UInt32($0) : nil }
        let purpose = call.string("purpose")
        let region = call.arguments["region"]?.object
        let windowID = call.string("window_id")

        let effectiveMode: String
        if windowID != nil || captureModeRaw == "window" {
            effectiveMode = "window"
        } else if region != nil || captureModeRaw == "region" {
            effectiveMode = "region"
        } else {
            effectiveMode = "fullscreen"
        }
        if effectiveMode == "window" {
            guard let windowID, !windowID.isEmpty else {
                throw MCPToolError("capture_mode \"window\" needs 'window_id' (e.g. 'window_12345' as listed by use_app list_windows).")
            }
        }
        if effectiveMode == "region" {
            guard let region,
                  let x = region["x"]?.double, let y = region["y"]?.double,
                  let w = region["width"]?.double, let h = region["height"]?.double,
                  w > 0, h > 0 else {
                throw MCPToolError("capture_mode \"region\" needs the interactive region-selection overlay, which SwiftCode's MCP host does not have; pass a 'region' object {x, y, width, height} (screen points, origin top-left of the main display) instead, or use capture_mode \"fullscreen\".")
            }
        }

        var png: Data
        var width: Int
        var height: Int
        var displayIDValue: UInt32

        if effectiveMode == "window" {
#if canImport(ScreenCaptureKit) && canImport(CoreGraphics)
            let windowShot = try await Self.terminalCaptureWindow(windowID: windowID!, includeCursor: includeCursor)
            png = windowShot.png
            width = windowShot.width
            height = windowShot.height
            displayIDValue = windowShot.displayID
#else
            throw MCPToolError("take_screenshot capture_mode \"window\" is only available on macOS (ScreenCaptureKit).")
#endif
        } else {
            let shot = try await terminalCaptureScreenshot(displayID: displayID, includeCursor: includeCursor)
            displayIDValue = shot.displayID
            if effectiveMode == "region" {
                let x = region!["x"]!.double!
                let y = region!["y"]!.double!
                let w = region!["width"]!.double!
                let h = region!["height"]!.double!
#if canImport(ScreenCaptureKit) && canImport(CoreGraphics)
                if let cropped = Self.terminalCropScreenshot(shot, to: CGRect(x: x, y: y, width: w, height: h)) {
                    png = cropped.png
                    width = cropped.width
                    height = cropped.height
                } else {
                    throw MCPToolError("The requested region (\(Int(x)), \(Int(y)) \(Int(w))x\(Int(h))) lies outside the captured display.")
                }
#else
                throw MCPToolError("take_screenshot capture_mode \"region\" is only available on macOS (ScreenCaptureKit).")
#endif
            } else {
                png = shot.png
                width = shot.width
                height = shot.height
            }
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let uniqueName = "screenshot_\(timestamp)_\(UUID().uuidString.prefix(8)).png"
        let rel = ".assist_temp/artifacts/\(uniqueName)"
        let url = artifactDirectory(in: s).appendingPathComponent(uniqueName)
        let description = purpose ?? "Screen capture (\(effectiveMode)) at \(width)x\(height)"
        try await approveFileWritingChange(tool: call.name, path: url, relativePath: rel, original: nil,
                                           summary: "Save screenshot artifact \(rel) (\(width)x\(height))", call: call)
        do {
            try FileManager.default.createDirectory(at: artifactDirectory(in: s), withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            try png.write(to: artifactDirectory(in: s).appendingPathComponent("image.png"), options: .atomic)
        } catch {
            throw MCPToolError("Captured screenshot successfully but failed to save artifact: \(error.localizedDescription)")
        }
        var index = loadFileReadingArtifactIndex(in: s)
        let entry = FileReadingArtifactIndexEntry(id: UUID(), description: description, kind: "image",
                                                 createdAt: Date(), sourceMessageID: nil)
        index[uniqueName] = entry
        var mirror = index["image.png"] ?? FileReadingArtifactIndexEntry(id: UUID(), description: "Latest screen capture",
                                                                          kind: "image", createdAt: Date(), sourceMessageID: nil)
        mirror.description = "Latest screen capture"
        index["image.png"] = mirror
        saveFileReadingArtifactIndex(index, in: s)
        noteFileWritingChanged(url, in: s)
        noteFileWritingChanged(artifactDirectory(in: s).appendingPathComponent("image.png"), in: s)

        let message = "Captured \(effectiveMode) screenshot (\(width)×\(height) px) on display \(displayIDValue). Artifact saved to '\(rel)'."
        var structured: [String: AnyJSON] = ["path": .string(rel), "width": .int(width), "height": .int(height),
                                             "display_id": .int(Int(displayIDValue)), "capture_mode": .string(effectiveMode),
                                             "artifact_id": .string(entry.id.uuidString),
                                             "base64": .string(png.base64EncodedString()),
                                             "format": .string("png"), "size_bytes": .int(png.count)]
        if let purpose { structured["purpose"] = .string(purpose) }
        let json = AnyJSON.object(structured)
        return MCPToolResult(content: [.imageBlock(png), .textBlock(message), .textBlock(json.text)],
                             structured: json)
    }

#if canImport(ScreenCaptureKit) && canImport(CoreGraphics)
    nonisolated static func terminalCaptureWindow(windowID: String, includeCursor: Bool) async throws -> TerminalScreenshot {
        let numberText = windowID.replacingOccurrences(of: "window_", with: "")
        guard let number = UInt32(numberText) else {
            throw MCPToolError("Invalid window_id '\(windowID)'. Use 'window_<CGWindowID>' as listed by use_app list_windows.")
        }
        guard terminalScreenCaptureAuthorizedStatic() else {
            throw MCPToolError("Screen Recording permission has not been granted. Please grant Screen Recording permission to SwiftCode in macOS System Settings > Privacy & Security > Screen Recording, then retry.")
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(number) }) else {
            throw MCPToolError("Window '\(windowID)' was not found among the on-screen windows.")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2
        config.showsCursor = includeCursor
        config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let pngData = terminalEncodePNGStatic(image) else {
            throw MCPToolError("Failed to encode the window screenshot as PNG.")
        }
        return TerminalScreenshot(png: pngData, width: image.width, height: image.height, displayID: CGMainDisplayID())
    }

    nonisolated static func terminalCropScreenshot(_ shot: TerminalScreenshot, to rect: CGRect) -> TerminalScreenshot? {
        guard let source = CGImageSourceCreateWithData(shot.png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let mainDisplayID = CGMainDisplayID()
        let dispBounds = CGDisplayBounds(mainDisplayID)
        guard dispBounds.width > 0 else { return nil }
        let scale = CGFloat(image.width) / dispBounds.width
        let cropRect = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale,
                              width: rect.width * scale, height: rect.height * scale).integral
        guard cropRect.width > 0, cropRect.height > 0,
              cropRect.minX >= 0, cropRect.minY >= 0,
              cropRect.maxX <= CGFloat(image.width), cropRect.maxY <= CGFloat(image.height),
              let cropped = image.cropping(to: cropRect),
              let png = terminalEncodePNGStatic(cropped) else { return nil }
        return TerminalScreenshot(png: png, width: cropped.width, height: cropped.height, displayID: shot.displayID)
    }
#endif
}

extension SwiftCodeMCPHost {
    nonisolated static func terminalScreenCaptureAuthorizedStatic() -> Bool {
#if canImport(CoreGraphics)
        if CGPreflightScreenCaptureAccess() { return true }
        _ = CGRequestScreenCaptureAccess()
        return false
#else
        return false
#endif
    }

    nonisolated static func terminalEncodePNGStatic(_ image: CGImage) -> Data? {
#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
#else
        return nil
#endif
    }
}
