import Foundation
import CoreGraphics
import AppKit

public struct AssistTakeScreenshotTool: AssistTool {
    public let id = "take_screenshot"
    public let name = "take_screenshot"
    public let description = "Captures the user's entire screen or a user-selected screen region, produces a valid PNG image, and makes the resulting image available to the active AI model for visual analysis."

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: description,
            properties: [
                "capture_mode": JSONSchema(
                    type: "string",
                    description: "Screen capture mode: 'fullscreen' for entire screen, or 'region' for an interactive user-selected region. Defaults to 'fullscreen'."
                ),
                "display_id": JSONSchema(
                    type: "integer",
                    description: "Optional display identifier when multiple displays are connected."
                ),
                "include_cursor": JSONSchema(
                    type: "boolean",
                    description: "Whether to include the mouse cursor in the capture. Defaults to true."
                ),
                "image_format": JSONSchema(
                    type: "string",
                    description: "Image output format. Must be 'png'. Defaults to 'png'."
                ),
                "purpose": JSONSchema(
                    type: "string",
                    description: "Optional explanation of what Assist needs to inspect in the screenshot."
                )
            ],
            required: []
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let captureMode = (input["capture_mode"] as? String)?.lowercased() ?? "fullscreen"
        let includeCursor = (input["include_cursor"] as? Bool) ?? true
        let displayIDRaw = input["display_id"] as? Int
        let displayID = displayIDRaw.map { CGDirectDisplayID($0) }
        let purpose = input["purpose"] as? String

        // Verify permission preflight
        guard AssistScreenCaptureEngine.shared.checkAuthorization(promptIfDenied: true) else {
            return AssistToolResult.failure(
                "Screen Recording permission has not been granted. Please grant Screen Recording permission to SwiftCode in macOS System Settings > Privacy & Security > Screen Recording, then retry.",
                diagnostics: ["Permission check failed: CGPreflightScreenCaptureAccess returned false."]
            )
        }

        let captureResult: ScreenCaptureResult
        do {
            if captureMode == "region" {
                captureResult = try await AssistScreenCaptureEngine.shared.captureUserSelectedRegion()
            } else {
                captureResult = try await AssistScreenCaptureEngine.shared.captureFullScreen(
                    displayID: displayID,
                    includeCursor: includeCursor
                )
            }
        } catch let err as ScreenCaptureError {
            switch err {
            case .regionSelectionCancelled:
                return AssistToolResult.failure(
                    "Region capture was cancelled by the user.",
                    diagnostics: ["User aborted interactive region selection overlay (Escape pressed or zero-area drag)."]
                )
            case .permissionDenied(let msg):
                return AssistToolResult.failure(
                    msg,
                    diagnostics: ["Screen capture denied by operating system."]
                )
            default:
                return AssistToolResult.failure(
                    "Failed to capture screen: \(err.localizedDescription)",
                    diagnostics: ["Capture error details: \(err)"]
                )
            }
        } catch {
            return AssistToolResult.failure(
                "Screen capture failed unexpectedly: \(error.localizedDescription)"
            )
        }

        // Generate artifact name with unique identifier to prevent collisions
        let timestamp = Int(Date().timeIntervalSince1970)
        let uniqueName = "screenshot_\(timestamp)_\(UUID().uuidString.prefix(8)).png"
        let description = purpose ?? "Screen capture (\(captureResult.captureMode)) at \(captureResult.width)x\(captureResult.height)"

        let artifactRecord: AssistArtifactRecord
        do {
            artifactRecord = try AssistArtifactStore.shared.createBinaryArtifact(
                name: uniqueName,
                data: captureResult.pngData,
                description: description,
                kind: .image,
                workspaceRoot: context.workspaceRoot
            )

            // Also maintain a well-known image.png copy in artifacts directory for backward compatibility
            _ = try? AssistArtifactStore.shared.createBinaryArtifact(
                name: "image.png",
                data: captureResult.pngData,
                description: "Latest screen capture",
                kind: .image,
                workspaceRoot: context.workspaceRoot
            )
        } catch {
            return AssistToolResult.failure(
                "Captured screenshot successfully but failed to save artifact: \(error.localizedDescription)"
            )
        }

        let base64String = captureResult.pngData.base64EncodedString()
        let outputMessage = "Captured \(captureResult.captureMode) screenshot (\(captureResult.width)×\(captureResult.height) px) on display \(captureResult.displayID). Artifact saved to '\(artifactRecord.relativePath)'."

        var data: [String: String] = [
            "path": artifactRecord.relativePath,
            "width": "\(captureResult.width)",
            "height": "\(captureResult.height)",
            "display_id": "\(captureResult.displayID)",
            "capture_mode": captureResult.captureMode,
            "artifact_id": artifactRecord.id.uuidString,
            "base64": base64String,
            "format": "png",
            "size_bytes": "\(captureResult.pngData.count)"
        ]
        if let purpose = purpose {
            data["purpose"] = purpose
        }

        return AssistToolResult.success(
            outputMessage,
            data: data
        )
    }
}
