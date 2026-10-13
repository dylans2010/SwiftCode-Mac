import Foundation
import SwiftCodeSDK

let args = Array(CommandLine.arguments.dropFirst())
let path = args.first ?? FileManager.default.currentDirectoryPath

let validator = ExtensionValidator()
let diags = validator.validateFile(at: path)

if diags.isEmpty {
    print("✅ Extension validation passed.")
    exit(0)
} else {
    print(DiagnosticFormatter.formatText(diags))
    let hasError = diags.contains { $0.severity == .error }
    exit(hasError ? 1 : 0)
}
