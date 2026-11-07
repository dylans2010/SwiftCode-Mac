import Foundation

public enum SDKAPIKeySessionAuth {

    public static let environmentVariableName = "SWIFTCODE_API_KEY"

    public static func presentedKeyFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let raw = environment[environmentVariableName] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
