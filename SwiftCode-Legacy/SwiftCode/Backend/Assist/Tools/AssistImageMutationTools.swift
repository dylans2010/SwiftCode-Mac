//
//  AssistImageMutationTools.swift
//  SwiftCode
//
//  Created on 2026-10-18.
//

import Foundation
import AppKit
import ImageIO
import CoreGraphics

// MARK: - Helper

private func resolveWorkspaceImageMutationURL(_ raw: String, workspaceRoot: URL) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
        return nil
    }
    let rootPath = workspaceRoot.standardized.path
    let candidate: URL
    if trimmed.hasPrefix("/") {
        candidate = URL(fileURLWithPath: trimmed).standardized
    } else {
        candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
    }
    let candidatePath = candidate.path
    guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
        return nil
    }
    return candidate
}

// MARK: - Image Decode Base64 Tool

public struct AssistImageDecodeBase64Tool: AssistTool {
    public let id = "image_decode_base64"
    public let name = "Decode Base64 to Image"
    public let description = "Decodes a Base64-encoded string into an image file (PNG, JPEG, TIFF, GIF) and saves it to disk."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Decodes a Base64-encoded string into an image file (PNG, JPEG, TIFF, GIF) and saves it to disk.",
            properties: [
                "base64String": JSONSchema(type: "string", description: "The base64 encoded image string (accepts raw base64 or data:image/...;base64,... URI)."),
                "destination": JSONSchema(type: "string", description: "Workspace-relative file path where the decoded image will be saved (e.g. Assets/icon.png).")
            ],
            required: ["base64String", "destination"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard var rawBase64 = (input["base64String"] ?? input["base64"] ?? input["data"]) as? String,
              let destRaw = (input["destination"] ?? input["destinationPath"] ?? input["path"]) as? String else {
            return .failure("Missing required parameters: base64String and destination")
        }

        if let commaIndex = rawBase64.firstIndex(of: ",") {
            let prefix = String(rawBase64[..<commaIndex])
            if prefix.contains(";base64") {
                rawBase64 = String(rawBase64[rawBase64.index(after: commaIndex)...])
            }
        }

        let cleaned = rawBase64.components(separatedBy: .whitespacesAndNewlines).joined()

        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters), !data.isEmpty else {
            return .failure("Failed to decode base64 string into valid binary data.")
        }

        guard let destURL = resolveWorkspaceImageMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        let parentDir = destURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        do {
            try data.write(to: destURL, options: .atomic)
            return .success(
                "Successfully decoded base64 string and saved image to `\(destRaw)` (\(data.count) bytes).",
                data: ["destination": destRaw, "size": "\(data.count)"],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to write image data to `\(destRaw)`: \(error.localizedDescription)")
        }
    }
}

// MARK: - Image Convert Format Tool

public struct AssistImageConvertFormatTool: AssistTool {
    public let id = "image_convert_format"
    public let name = "Convert Image Format"
    public let description = "Converts an image file between formats (png, jpeg, tiff, bmp, gif) with optional compression quality."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Converts an image file between formats (png, jpeg, tiff, bmp, gif) with optional compression quality.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the source image."),
                "format": JSONSchema(type: "string", description: "Target image format: 'png', 'jpeg', 'jpg', 'tiff', 'bmp', or 'gif'."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative destination path. Defaults to source path with new extension."),
                "quality": JSONSchema(type: "number", description: "Compression quality for JPEG/HEIC (0.0 to 1.0). Default: 0.9.")
            ],
            required: ["path", "format"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["source"]) as? String,
              let formatRaw = (input["format"] as? String)?.lowercased() else {
            return .failure("Missing required parameters: path and format")
        }

        guard let sourceURL = resolveWorkspaceImageMutationURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source path is outside the workspace: \(sourceRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Source image not found at: \(sourceRaw)")
        }

        guard let nsImage = NSImage(contentsOf: sourceURL),
              let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return .failure("Failed to read and decode image at: \(sourceRaw)")
        }

        let fileType: NSBitmapImageRep.FileType
        let ext: String
        switch formatRaw {
        case "png":
            fileType = .png
            ext = "png"
        case "jpeg", "jpg":
            fileType = .jpeg
            ext = "jpg"
        case "tiff", "tif":
            fileType = .tiff
            ext = "tiff"
        case "bmp":
            fileType = .bmp
            ext = "bmp"
        case "gif":
            fileType = .gif
            ext = "gif"
        default:
            return .failure("Unsupported target format '\(formatRaw)'. Supported formats: png, jpeg, tiff, bmp, gif.")
        }

        let quality = (input["quality"] as? Double) ?? 0.9
        var props: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if fileType == .jpeg {
            props[.compressionFactor] = NSNumber(value: quality)
        }

        guard let outputData = bitmap.representation(using: fileType, properties: props) else {
            return .failure("Failed to convert image to \(formatRaw) format.")
        }

        let defaultDest = (sourceRaw as NSString).deletingPathExtension + ".\(ext)"
        let destRaw = (input["destination"] as? String) ?? defaultDest

        guard let destURL = resolveWorkspaceImageMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        let parentDir = destURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        do {
            try outputData.write(to: destURL, options: .atomic)
            return .success(
                "Successfully converted `\(sourceRaw)` to \(formatRaw.uppercased()) at `\(destRaw)` (\(outputData.count) bytes).",
                data: ["destination": destRaw, "size": "\(outputData.count)", "format": formatRaw],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to write converted image to `\(destRaw)`: \(error.localizedDescription)")
        }
    }
}

// MARK: - Image Generate Thumbnail Tool

public struct AssistImageGenerateThumbnailTool: AssistTool {
    public let id = "image_generate_thumbnail"
    public let name = "Generate Image Thumbnail"
    public let description = "Generates a scaled thumbnail image maintaining aspect ratio and writes it to disk."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Generates a scaled thumbnail image maintaining aspect ratio and writes it to disk.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the source image."),
                "maxPixelSize": JSONSchema(type: "integer", description: "Maximum width or height of the thumbnail in pixels (e.g. 256). Default: 256."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative path for output thumbnail. Defaults to <name>_thumb.png.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["source"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let sourceURL = resolveWorkspaceImageMutationURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source path is outside the workspace: \(sourceRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("Source image not found at: \(sourceRaw)")
        }

        let maxPixelSize = (input["maxPixelSize"] as? Int) ?? 256
        guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return .failure("Could not read image source at: \(sourceRaw)")
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnailCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return .failure("Failed to create thumbnail from image: \(sourceRaw)")
        }

        let bitmap = NSBitmapImageRep(cgImage: thumbnailCG)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .failure("Failed to encode thumbnail into PNG data.")
        }

        let baseName = (sourceRaw as NSString).deletingPathExtension
        let defaultDest = "\(baseName)_thumb.png"
        let destRaw = (input["destination"] as? String) ?? defaultDest

        guard let destURL = resolveWorkspaceImageMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        let parentDir = destURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        do {
            try pngData.write(to: destURL, options: .atomic)
            let thumbWidth = thumbnailCG.width
            let thumbHeight = thumbnailCG.height
            return .success(
                "Successfully generated \(thumbWidth)x\(thumbHeight) thumbnail for `\(sourceRaw)` at `\(destRaw)` (\(pngData.count) bytes).",
                data: [
                    "destination": destRaw,
                    "width": "\(thumbWidth)",
                    "height": "\(thumbHeight)",
                    "size": "\(pngData.count)"
                ],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to write thumbnail to `\(destRaw)`: \(error.localizedDescription)")
        }
    }
}

// MARK: - SVG to PNG Tool

public struct AssistSvgToPngTool: AssistTool {
    public let id = "svg_to_png"
    public let name = "Convert SVG to PNG"
    public let description = "Renders an SVG vector graphic into a raster PNG image file at a specified scale or dimensions."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Renders an SVG vector graphic into a raster PNG image file at a specified scale or dimensions.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .svg file."),
                "destination": JSONSchema(type: "string", description: "Optional workspace-relative destination path for .png. Defaults to <path>.png."),
                "scale": JSONSchema(type: "number", description: "Scale multiplier for rendering (e.g. 1.0, 2.0 for @2x, 3.0 for @3x). Default: 2.0."),
                "width": JSONSchema(type: "integer", description: "Explicit width in pixels (optional; overrides scale if provided)."),
                "height": JSONSchema(type: "integer", description: "Explicit height in pixels (optional; overrides scale if provided).")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let sourceRaw = (input["path"] ?? input["source"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let sourceURL = resolveWorkspaceImageMutationURL(sourceRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Source path is outside the workspace: \(sourceRaw)")
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure("SVG file not found at: \(sourceRaw)")
        }

        guard let nsImage = NSImage(contentsOf: sourceURL) else {
            return .failure("Failed to parse and render SVG at: \(sourceRaw)")
        }

        var targetSize = nsImage.size
        if targetSize.width <= 0 || targetSize.height <= 0 {
            targetSize = NSSize(width: 512, height: 512)
        }

        if let explicitWidth = input["width"] as? Int, let explicitHeight = input["height"] as? Int, explicitWidth > 0, explicitHeight > 0 {
            targetSize = NSSize(width: explicitWidth, height: explicitHeight)
        } else {
            let scale = (input["scale"] as? Double) ?? 2.0
            targetSize = NSSize(width: targetSize.width * scale, height: targetSize.height * scale)
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return .failure("Failed to allocate bitmap representation for SVG rendering.")
        }

        bitmap.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        guard let contextRef = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return .failure("Failed to create graphics context for bitmap.")
        }
        NSGraphicsContext.current = contextRef

        nsImage.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: nsImage.size),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return .failure("Failed to encode rendered SVG into PNG format.")
        }

        let baseName = (sourceRaw as NSString).deletingPathExtension
        let defaultDest = "\(baseName).png"
        let destRaw = (input["destination"] as? String) ?? defaultDest

        guard let destURL = resolveWorkspaceImageMutationURL(destRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Destination path is outside the workspace: \(destRaw)")
        }

        let parentDir = destURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        do {
            try pngData.write(to: destURL, options: .atomic)
            return .success(
                "Successfully rendered SVG `\(sourceRaw)` to PNG `\(destRaw)` (\(Int(targetSize.width))x\(Int(targetSize.height)), \(pngData.count) bytes).",
                data: [
                    "destination": destRaw,
                    "width": "\(Int(targetSize.width))",
                    "height": "\(Int(targetSize.height))",
                    "size": "\(pngData.count)"
                ],
                filesChanged: [destRaw]
            )
        } catch {
            return .failure("Failed to write rendered PNG to `\(destRaw)`: \(error.localizedDescription)")
        }
    }
}
