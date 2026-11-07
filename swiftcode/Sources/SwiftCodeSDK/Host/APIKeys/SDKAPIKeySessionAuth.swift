import Foundation

public enum SDKAPIKeySessionAuth {
    public static let environmentVariable = "SWIFTCODE_API_KEY"

    public static func presentedKeyFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let raw = environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }
}
