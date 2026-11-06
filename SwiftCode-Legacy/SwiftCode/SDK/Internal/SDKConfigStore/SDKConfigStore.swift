#if DEBUG

import Foundation

/// Canonical SDK version metadata decoded from
/// `SwiftCode/SDK/Internal/SDKConfigStore/SwiftCodeSDK.json`.
///
/// Managed by internal developers; user projects' SDK bindings sync from
/// this file on launch (non-breaking updates propagate automatically,
/// breaking updates require an explicit Studio prompt). Internal only —
/// stripped from release builds.
public struct SDKConfig: Codable, Sendable {
    /// SDK package version (e.g. "1.0.0").
    public let sdkVersion: String
    /// Internal API version (e.g. "2026.1").
    public let apiVersion: String
    /// Minimum SwiftCode host version that can load this SDK.
    public let minimumHostVersion: String
    /// Host/runtime wire protocol version.
    public let protocolVersion: Int
    /// Human-readable release notes shown in the Studio notification panel.
    public let releaseNotes: [String]
    /// ISO-8601 timestamp of the last metadata update.
    public let updateTimestamp: String
    /// Names of deprecated public APIs (empty in 1.0.0).
    public let deprecatedAPIs: [String]
}

/// Errors thrown by ``SDKConfigStore/load()``.
public enum SDKConfigError: Error, LocalizedError {
    /// `SwiftCodeSDK.json` is not present in the app bundle (it was not
    /// added to the target's Copy Bundle Resources phase).
    case missingResource
    /// The resource exists but could not be read.
    case unreadable(Error)
    /// The resource content is not valid SDK metadata JSON.
    case decoding(Error)

    public var errorDescription: String? {
        switch self {
        case .missingResource:
            return "SwiftCodeSDK.json is missing from the app bundle. " +
                "The coordinator must add SwiftCode/SDK/Internal/SDKConfigStore/SwiftCodeSDK.json " +
                "to the SwiftCode target's Copy Bundle Resources build phase."
        case .unreadable(let error):
            return "SwiftCodeSDK.json could not be read: \(error.localizedDescription)"
        case .decoding(let error):
            return "SwiftCodeSDK.json could not be decoded as SDKConfig: \(error.localizedDescription)"
        }
    }
}

/// DEBUG-only reader for the canonical SDK version metadata.
///
/// Compiled only under `#if DEBUG`; entirely absent from release builds.
public enum SDKConfigStore {
    /// Loads the canonical SDK configuration from the app bundle.
    ///
    /// - Returns: The decoded ``SDKConfig``.
    /// - Throws: ``SDKConfigError`` if the JSON is missing, unreadable,
    ///   or fails to decode.
    public static func load() throws -> SDKConfig {
        guard let url = Bundle.main.url(forResource: "SwiftCodeSDK", withExtension: "json") else {
            throw SDKConfigError.missingResource
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SDKConfigError.unreadable(error)
        }
        do {
            return try JSONDecoder().decode(SDKConfig.self, from: data)
        } catch {
            throw SDKConfigError.decoding(error)
        }
    }

    /// Returns whether the named public API is listed as deprecated in
    /// the given configuration.
    public static func isDeprecated(api: String, in config: SDKConfig) -> Bool {
        config.deprecatedAPIs.contains(api)
    }
}

#endif
