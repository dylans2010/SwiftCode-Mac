import Foundation

/// `extension-validator` tool (Legacy `Sources/Tools/ExtensionValidator/main.swift`).
///
/// Validates an extension manifest (file or directory) through
/// `SDKManifestValidator`, the adapter over SwiftCodeExtensions' strict
/// validator — not Legacy's lenient validator, which was deliberately not
/// reimplemented (spec §2.3). Library entry point: the executable target
/// wraps it in a thin `@main` that calls
/// `exit(ExtensionValidatorMain.run(...))`.
public enum ExtensionValidatorMain {
    public static func run(arguments: [String]) -> Int32 {
        let path = arguments.first ?? FileManager.default.currentDirectoryPath

        let validator = SDKManifestValidator()
        let diags = validator.validateFile(at: path)

        if diags.isEmpty {
            print("✅ Extension validation passed.")
            return 0
        } else {
            print(DiagnosticFormatter.formatText(diags))
            let hasError = diags.contains { $0.severity == .error }
            return hasError ? 1 : 0
        }
    }
}
