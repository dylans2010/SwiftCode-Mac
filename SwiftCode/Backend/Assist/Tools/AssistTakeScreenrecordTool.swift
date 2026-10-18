import Foundation
import CoreGraphics
import AppKit

public struct AssistTakeScreenrecordTool: AssistTool {
    public let id = "take_screenrecord"
    public let name = "take_screenrecord"
    public let description = "Records the screen of a specifically identified application, subject to macOS privacy permissions and recording restrictions, and produces a usable recording artifact."

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: description,
            properties: [
                "app_identifier": JSONSchema(
                    type: "string",
                    description: "Target application bundle identifier (e.g. 'com.apple.dt.Xcode') or application name (e.g. 'Xcode'). Preferred: bundle identifier."
                ),
                "recording_duration": JSONSchema(
                    type: "number",
                    description: "Requested recording duration in seconds (between 1 and 60). Defaults to 10 seconds."
                ),
                "capture_mode": JSONSchema(
                    type: "string",
                    description: "Capture scope: 'window' for the application's primary on-screen window, or 'application_display'. Defaults to 'window'."
                ),
                "include_audio": JSONSchema(
                    type: "boolean",
                    description: "Whether to capture application audio when supported. Defaults to false."
                ),
                "output_format": JSONSchema(
                    type: "string",
                    description: "Video container format. Supported: 'mov', 'mp4'. Defaults to 'mov'."
                ),
                "purpose": JSONSchema(
                    type: "string",
                    description: "Optional natural-language explanation of why Assist is recording this application."
                )
            ],
            required: ["app_identifier"]
        )
    }

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawAppId = input["app_identifier"] as? String,
              !rawAppId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AssistToolResult.failure(
                "Missing required parameter 'app_identifier'. Provide a bundle identifier or application name."
            )
        }
        let appIdentifier = rawAppId.trimmingCharacters(in: .whitespacesAndNewlines)

        let durationSeconds: TimeInterval
        if let d = input["recording_duration"] as? Double {
            durationSeconds = d
        } else if let d = input["recording_duration"] as? Int {
            durationSeconds = Double(d)
        } else {
            durationSeconds = 10.0
        }

        guard durationSeconds >= 1 && durationSeconds <= 60 else {
            return AssistToolResult.failure(
                "Requested recording duration (\(durationSeconds)s) is invalid. Duration must be between 1 and 60 seconds."
            )
        }

        let captureMode = (input["capture_mode"] as? String)?.lowercased() ?? "window"
        let includeAudio = (input["include_audio"] as? Bool) ?? false
        let outputFormat = (input["output_format"] as? String)?.lowercased() == "mp4" ? "mp4" : "mov"
        let purpose = input["purpose"] as? String

        // Preflight Screen Recording permission
        guard AssistScreenCaptureEngine.shared.checkAuthorization(promptIfDenied: true) else {
            return AssistToolResult.failure(
                "Screen Recording permission has not been granted. Grant Screen Recording permission to SwiftCode in macOS System Settings > Privacy & Security > Screen Recording, then retry.",
                diagnostics: ["Permission check failed: CGPreflightScreenCaptureAccess returned false."]
            )
        }

        let recordResult: ScreenRecordResult
        do {
            recordResult = try await AssistScreenRecordingEngine.shared.recordApplication(
                appIdentifier: appIdentifier,
                durationSeconds: durationSeconds,
                captureMode: captureMode,
                includeAudio: includeAudio,
                outputFormat: outputFormat
            )
        } catch let err as ScreenRecordError {
            switch err {
            case .appNotFound(let id):
                return AssistToolResult.failure(
                    "Application '\(id)' could not be resolved or is not running. Please launch the target application before attempting to record its screen.",
                    diagnostics: ["Target application resolution failed: no running process matched '\(id)'."]
                )
            case .noEligibleWindows(let app):
                return AssistToolResult.failure(
                    "No visible on-screen windows were found for application '\(app)'. Make sure the application is open and not minimized or hidden.",
                    diagnostics: ["Window query returned 0 visible windows for PID."]
                )
            case .permissionDenied(let msg):
                return AssistToolResult.failure(msg)
            default:
                return AssistToolResult.failure(
                    "Screen recording failed: \(err.localizedDescription)",
                    diagnostics: ["Recording error details: \(err)"]
                )
            }
        } catch {
            return AssistToolResult.failure(
                "Screen recording failed unexpectedly: \(error.localizedDescription)"
            )
        }

        // Save recording artifact
        let timestamp = Int(Date().timeIntervalSince1970)
        let safeAppName = recordResult.appName.replacingOccurrences(of: " ", with: "_").lowercased()
        let artifactName = "screenrecord_\(safeAppName)_\(timestamp).\(recordResult.outputFormat)"
        let desc = purpose ?? "Screen recording of \(recordResult.appName) (\(Int(recordResult.duration))s, \(recordResult.width)x\(recordResult.height))"

        let artifactRecord: AssistArtifactRecord
        do {
            artifactRecord = try AssistArtifactStore.shared.createBinaryArtifact(
                name: artifactName,
                data: recordResult.data,
                description: desc,
                kind: .screenRecording,
                workspaceRoot: context.workspaceRoot
            )
        } catch {
            return AssistToolResult.failure(
                "Completed recording of \(recordResult.appName), but failed to save artifact: \(error.localizedDescription)"
            )
        }

        let outputMessage = "Recorded \(Int(recordResult.duration))s of '\(recordResult.appName)' (\(recordResult.appBundleID)) at \(recordResult.width)×\(recordResult.height) px. Artifact saved to '\(artifactRecord.relativePath)'."

        var data: [String: String] = [
            "path": artifactRecord.relativePath,
            "duration": "\(recordResult.duration)",
            "width": "\(recordResult.width)",
            "height": "\(recordResult.height)",
            "app_identifier": recordResult.appBundleID,
            "app_name": recordResult.appName,
            "artifact_id": artifactRecord.id.uuidString,
            "format": recordResult.outputFormat,
            "size_bytes": "\(recordResult.data.count)"
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
