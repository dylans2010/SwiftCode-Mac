import Foundation

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
