import Foundation
import SwiftCodeExtensions

/// Bridges the already-ported manifest surface to the SDK diagnostic model.
///
/// Legacy's lenient `ExtensionValidator` (validate a manifest value, or a
/// file at a path, returning `[Diagnostic]`) was deliberately NOT
/// reimplemented — the SwiftCode port uses the strict
/// `SwiftCodeManifestValidator` from `SwiftCodeExtensions` (spec §2.3). This
/// adapter preserves the kit-level call shape (`validateFile(at:)`) that
/// `ExtensionPackager`, the CLI, and the tools relied on, mapping each
/// `ManifestDiagnostic` onto an SDK `Diagnostic`.
///
/// Mapping rules:
/// - severity `.error` → `.error`, `.warning` → `.warning`, `.info` → `.note`.
/// - code: `manifest` field → `.manifestInvalidJSON`; missing-field errors
///   → `.manifestMissingRequiredField`; `manifestVersion` → `.manifestInvalidVersion`;
///   `capabilities` → `.manifestUnauthorizedCapability`; everything else
///   → `.manifestInvalidJSON` for errors, `.manifestInvalidCapabilityReason`
///   for warnings. The validator's message is kept verbatim; its suggestion
///   becomes the remediation; the line becomes a location only when the
///   package root is known (otherwise the diagnostic is global).
public struct SDKManifestValidator: Sendable {
    public init() {}

    /// Validates already-read manifest bytes. `packageRoot` is used only to
    /// anchor the reported location; pass nil for a global diagnostic.
    public func validate(data: Data, packageRoot: String? = nil) -> [Diagnostic] {
        let diags = SwiftCodeManifestValidator.validateWithDiagnostics(
            data: data,
            projectRoot: packageRoot.map { URL(fileURLWithPath: $0) }
        )
        return diags.map { map($0, packageRoot: packageRoot) }
    }

    /// Validates the `swiftcode.json` at `path`, whether `path` is the
    /// manifest file itself or the directory containing it. Mirrors Legacy's
    /// `ExtensionValidator.validateFile(at:)`.
    public func validateFile(at path: String) -> [Diagnostic] {
        let ws = Workspace(path: path)
        let manifestPath: String
        let root: String
        if ws.fileAccess.exists(at: "swiftcode.json") {
            manifestPath = "swiftcode.json"
            root = ws.root.normalizedPath
        } else if (path as NSString).lastPathComponent == "swiftcode.json",
                  FileManager.default.fileExists(atPath: path) {
            manifestPath = path
            root = (path as NSString).deletingLastPathComponent
        } else {
            return [Diagnostic(
                code: .manifestNotFound,
                severity: .error,
                message: "Manifest not found at '\(path)'",
                remediation: "Provide a swiftcode.json manifest in the extension directory"
            )]
        }
        do {
            let data = try ws.fileAccess.readFile(at: manifestPath)
            return validate(data: data, packageRoot: root)
        } catch {
            return [Diagnostic(
                code: .manifestInvalidJSON,
                severity: .error,
                message: "Manifest could not be read: \(error.localizedDescription)"
            )]
        }
    }

    /// Decodes and validates in one step; throws the first error diagnostic
    /// as a `SwiftCodeExtensionError.manifest`, matching
    /// `SwiftCodeManifestValidator.validate(data:)`.
    public func validateAndDecode(data: Data) throws -> SwiftCodeManifest {
        try SwiftCodeManifestValidator.validate(data: data)
    }

    private func map(_ diag: ManifestDiagnostic, packageRoot: String?) -> Diagnostic {
        let severity: DiagnosticSeverity
        switch diag.severity {
        case .error: severity = .error
        case .warning: severity = .warning
        case .info: severity = .note
        }
        let code: DiagnosticCode
        switch (diag.field, severity) {
        case ("manifest", _): code = .manifestInvalidJSON
        case ("manifestVersion", _): code = .manifestInvalidVersion
        case ("capabilities", .error): code = .manifestUnauthorizedCapability
        case (_, .error): code = .manifestMissingRequiredField
        default: code = .manifestInvalidCapabilityReason
        }
        let location: DiagnosticLocation?
        if let line = diag.line, let root = packageRoot {
            location = DiagnosticLocation(filePath: (root as NSString).appendingPathComponent("swiftcode.json"), line: line)
        } else {
            location = nil
        }
        return Diagnostic(
            code: code,
            severity: severity,
            message: diag.message,
            location: location,
            remediation: diag.suggestion.isEmpty ? nil : diag.suggestion,
            metadata: ["field": diag.field]
        )
    }
}
