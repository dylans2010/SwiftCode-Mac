//
//  AssistImageInspectionTools.swift
//  SwiftCode
//
//  Created on 2026-10-18.
//

import Foundation
import ImageIO
import CoreGraphics

// MARK: - Helper

private func resolveWorkspaceImageInspectionURL(_ raw: String, workspaceRoot: URL) -> URL? {
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

// MARK: - Image Encode Base64 Tool (safeRead)

public struct AssistImageEncodeBase64Tool: AssistTool {
    public let id = "image_encode_base64"
    public let name = "Encode Image to Base64"
    public let description = "Reads an image file from the workspace and encodes it into a Base64 string or Data URI."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reads an image file from the workspace and encodes it into a Base64 string or Data URI.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the image file."),
                "includeDataUri": JSONSchema(type: "boolean", description: "Whether to return as a full data:image/<type>;base64,... URI. Defaults to false.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["filePath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceImageInspectionURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("Image file not found at: \(pathRaw)")
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let base64 = data.base64EncodedString()
            let includeUri = (input["includeDataUri"] as? Bool) ?? false

            let mimeType: String
            switch fileURL.pathExtension.lowercased() {
            case "png": mimeType = "image/png"
            case "jpg", "jpeg": mimeType = "image/jpeg"
            case "gif": mimeType = "image/gif"
            case "webp": mimeType = "image/webp"
            case "svg": mimeType = "image/svg+xml"
            case "tif", "tiff": mimeType = "image/tiff"
            default: mimeType = "application/octet-stream"
            }

            let resultString = includeUri ? "data:\(mimeType);base64,\(base64)" : base64
            let preview = String(resultString.prefix(100)) + "..."

            return .success(
                "Successfully encoded `\(pathRaw)` into Base64 (\(data.count) bytes raw, \(base64.count) chars base64).\nPreview: \(preview)",
                data: [
                    "path": pathRaw,
                    "mimeType": mimeType,
                    "byteCount": "\(data.count)",
                    "charCount": "\(resultString.count)",
                    "base64": resultString
                ]
            )
        } catch {
            return .failure("Failed to read image file `\(pathRaw)`: \(error.localizedDescription)")
        }
    }
}

// MARK: - Image Get Dimensions Tool (safeRead)

public struct AssistImageGetDimensionsTool: AssistTool {
    public let id = "image_get_dimensions"
    public let name = "Get Image Dimensions and Specs"
    public let description = "Extracts image dimensions (width, height), scale, color space, and format without loading full bitmap."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Extracts image dimensions (width, height), scale, color space, and format without loading full bitmap.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the image file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["filePath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceImageInspectionURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("Image file not found at: \(pathRaw)")
        }

        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return .failure("Could not create image source for: \(pathRaw)")
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return .failure("Could not read image properties from: \(pathRaw)")
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let dpiWidth = properties[kCGImagePropertyDPIWidth] as? Double ?? 72.0
        let dpiHeight = properties[kCGImagePropertyDPIHeight] as? Double ?? 72.0
        let colorModel = properties[kCGImagePropertyColorModel] as? String ?? "Unknown"
        let depth = properties[kCGImagePropertyDepth] as? Int ?? 8
        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let typeIdentifier = CGImageSourceGetType(imageSource) as String? ?? fileURL.pathExtension

        let output = """
        Image Specifications for \(pathRaw):
        - Dimensions: \(width) x \(height) pixels
        - Aspect Ratio: \(height > 0 ? String(format: "%.2f", Double(width) / Double(height)) : "N/A")
        - Color Model: \(colorModel) (\(depth)-bit)
        - Has Alpha Channel: \(hasAlpha ? "Yes" : "No")
        - Resolution: \(Int(dpiWidth)) x \(Int(dpiHeight)) DPI
        - Format / UTI: \(typeIdentifier)
        """

        return .success(
            output,
            data: [
                "path": pathRaw,
                "width": "\(width)",
                "height": "\(height)",
                "colorModel": colorModel,
                "depth": "\(depth)",
                "hasAlpha": "\(hasAlpha)",
                "format": typeIdentifier
            ]
        )
    }
}

// MARK: - Image Extract Metadata Tool (safeRead)

public struct AssistImageExtractMetadataTool: AssistTool {
    public let id = "image_extract_metadata"
    public let name = "Extract Image Metadata"
    public let description = "Extracts all embedded EXIF, TIFF, GPS, and camera metadata from an image as structured JSON."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Extracts all embedded EXIF, TIFF, GPS, and camera metadata from an image as structured JSON.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the image file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pathRaw = (input["path"] ?? input["filePath"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        guard let fileURL = resolveWorkspaceImageInspectionURL(pathRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Path is outside the workspace: \(pathRaw)")
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failure("Image file not found at: \(pathRaw)")
        }

        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return .failure("Could not read image source at: \(pathRaw)")
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return .failure("No metadata properties found in image at: \(pathRaw)")
        }

        var sanitized: [String: Any] = [:]
        for (k, v) in properties {
            if JSONSerialization.isValidJSONObject([k: v]) {
                sanitized[k] = v
            } else {
                sanitized[k] = String(describing: v)
            }
        }

        let jsonString: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: jsonData, encoding: .utf8) {
            jsonString = str
        } else {
            jsonString = "\(sanitized)"
        }

        return .success(
            "Extracted metadata from `\(pathRaw)` (\(sanitized.count) property groups):\n\(jsonString)",
            data: [
                "path": pathRaw,
                "metadataCount": "\(sanitized.count)",
                "metadataJSON": jsonString
            ]
        )
    }
}
