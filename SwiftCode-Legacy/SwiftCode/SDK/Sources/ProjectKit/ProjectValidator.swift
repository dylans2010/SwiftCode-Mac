import Foundation
import DiagnosticsKit
import WorkspaceKit

public final class ProjectValidator: Sendable {
    public init() {}

    public func validate(metadata: ProjectMetadata) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        // Validate identifier format
        let id = metadata.id
        if id.isEmpty {
            diagnostics.append(Diagnostic(
                code: .projectInvalidIdentifier,
                severity: .error,
                message: "Project identifier cannot be empty",
                remediation: "Provide a reverse-DNS style identifier such as 'com.example.myproject'"
            ))
        } else if id.contains(" ") {
            diagnostics.append(Diagnostic(
                code: .projectInvalidIdentifier,
                severity: .error,
                message: "Project identifier '\(id)' contains spaces",
                remediation: "Remove spaces and use alphanumeric characters with dots or dashes"
            ))
        }

        // Validate root path existence
        let ws = Workspace(path: metadata.rootPath)
        if !FileManager.default.fileExists(atPath: ws.root.normalizedPath) {
            diagnostics.append(Diagnostic(
                code: .projectNotFound,
                severity: .error,
                message: "Project root directory not found at '\(metadata.rootPath)'",
                remediation: "Verify the directory path exists"
            ))
        }

        // Validate targets
        if metadata.targets.isEmpty {
            diagnostics.append(Diagnostic(
                code: .projectMissingTarget,
                severity: .warning,
                message: "Project has no declared targets",
                remediation: "Add at least one library or executable target to the project"
            ))
        }

        return diagnostics
    }
}
