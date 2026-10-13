import Foundation
import DiagnosticsKit
import WorkspaceKit

public final class ExtensionValidator: Sendable {
    public init() {}

    public func validate(manifest: ExtensionManifest, packageRoot: String? = nil) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        // Manifest version
        if manifest.manifestVersion != 1 {
            diagnostics.append(Diagnostic(
                code: .manifestInvalidVersion,
                severity: .error,
                message: "Unsupported manifestVersion: \(manifest.manifestVersion). Expected 1.",
                remediation: "Set 'manifestVersion': 1 in swiftcode.json"
            ))
        }

        // Extension ID
        if manifest.id.isEmpty {
            diagnostics.append(Diagnostic(
                code: .manifestMissingRequiredField,
                severity: .error,
                message: "Extension ID cannot be empty",
                remediation: "Provide a reverse-DNS identifier (e.g. 'com.example.myextension')"
            ))
        } else if manifest.id.contains(" ") {
            diagnostics.append(Diagnostic(
                code: .manifestMissingRequiredField,
                severity: .error,
                message: "Extension ID '\(manifest.id)' contains whitespace",
                remediation: "Use dot-separated alphanumeric characters"
            ))
        }

        // Name
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(Diagnostic(
                code: .manifestMissingRequiredField,
                severity: .error,
                message: "Extension name cannot be empty",
                remediation: "Provide a human-readable name in swiftcode.json"
            ))
        }

        // Semver version
        let semverParts = manifest.version.components(separatedBy: ".")
        if semverParts.count != 3 || semverParts.contains(where: { Int($0) == nil }) {
            diagnostics.append(Diagnostic(
                code: .manifestInvalidVersion,
                severity: .error,
                message: "Invalid version string '\(manifest.version)'. Expected SemVer 'MAJOR.MINOR.PATCH'",
                remediation: "Format version as three dot-separated numbers, e.g. '1.0.0'"
            ))
        }

        // Entrypoint
        let ep = manifest.runtime.entrypoint
        if ep.hasPrefix("/") || ep.contains("..") {
            diagnostics.append(Diagnostic(
                code: .manifestInvalidEntrypoint,
                severity: .error,
                message: "Entrypoint '\(ep)' must be a safe relative path without traversal",
                remediation: "Set entrypoint relative to package root, e.g. 'dist/index.js'"
            ))
        }

        // Protocol version
        if manifest.sdk.protocolVersion != 1 {
            diagnostics.append(Diagnostic(
                code: .manifestUnsupportedProtocol,
                severity: .error,
                message: "Unsupported protocolVersion: \(manifest.sdk.protocolVersion). Host requires 1.",
                remediation: "Set 'protocolVersion': 1 in sdk section"
            ))
        }

        // Capabilities validation
        for cap in manifest.capabilities {
            if ExtensionCapabilityID(rawValue: cap.id) == nil {
                diagnostics.append(Diagnostic(
                    code: .manifestUnauthorizedCapability,
                    severity: .error,
                    message: "Unknown or invalid capability ID: '\(cap.id)'",
                    remediation: "Use one of the recognized SwiftCode capability IDs"
                ))
            }

            if cap.reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 8 {
                diagnostics.append(Diagnostic(
                    code: .manifestInvalidCapabilityReason,
                    severity: .warning,
                    message: "Capability '\(cap.id)' reason is too short",
                    remediation: "Provide a clear, human-readable justification for user approval"
                ))
            }
        }

        // Check file existence if packageRoot is provided
        if let root = packageRoot {
            let ws = Workspace(path: root)
            if !ws.fileAccess.exists(at: ep) {
                diagnostics.append(Diagnostic(
                    code: .manifestInvalidEntrypoint,
                    severity: .warning,
                    message: "Runtime entrypoint file not found on disk: '\(ep)'",
                    location: DiagnosticLocation(filePath: ws.root.appending(ep).normalizedPath),
                    remediation: "Compile your extension sources before packaging to generate \(ep)"
                ))
            }
        }

        return diagnostics
    }

    public func validateFile(at path: String) -> [Diagnostic] {
        let ws = Workspace(path: path)
        let manifestPath = ws.root.appending("swiftcode.json").normalizedPath

        guard FileManager.default.fileExists(atPath: manifestPath) else {
            return [Diagnostic(
                code: .manifestNotFound,
                severity: .error,
                message: "swiftcode.json not found at '\(path)'",
                location: DiagnosticLocation(filePath: manifestPath),
                remediation: "Create a valid swiftcode.json manifest in the extension directory"
            )]
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
            let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
            return validate(manifest: manifest, packageRoot: path)
        } catch {
            return [Diagnostic(
                code: .manifestInvalidJSON,
                severity: .error,
                message: "Failed parsing swiftcode.json: \(error.localizedDescription)",
                location: DiagnosticLocation(filePath: manifestPath),
                remediation: "Ensure swiftcode.json contains valid JSON conforming to swiftcode-extension-v1 schema"
            )]
        }
    }
}
