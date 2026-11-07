import Foundation
import SwiftCodeExtensions

public struct SDKManifestValidator: Sendable {
    public init() {}

    public func validate(data: Data, packageRoot: String? = nil) -> [Diagnostic] {
        let diags = SwiftCodeManifestValidator.validateWithDiagnostics(
            data: data,
            projectRoot: packageRoot.map { URL(fileURLWithPath: $0) }
        )
        return diags.map { map($0, packageRoot: packageRoot) }
    }

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
