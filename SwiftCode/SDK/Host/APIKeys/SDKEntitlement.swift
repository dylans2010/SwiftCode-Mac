import Foundation

// MARK: - SDKEntitlement
//
// A key-bound entitlement carried by a developer API key
// (Docs/Intro-to-SDK.md §12 — Part B Assist authorization).
//
// Entitlements differ from `SDKAPIKeyScope`: scopes describe what the key
// may DO on the platform (create apps, request capabilities), while
// entitlements unlock specific SDK surfaces for third-party apps after
// passing the Assist access application flow. Like scopes, the type is
// intentionally open — `init?(rawValue:)` accepts any non-empty string so
// that future entitlements decode from stored key metadata without
// breaking older hosts. Encoding is the bare entitlement string.
//
// The two v1 entitlements (exact identifiers; do not change them):
//   - `com.SwiftCode.developer-AI-Assist` — unlocks the Assist SDK
//     variants (`assistSDK.UI` / `assistSDK`).
//   - `com.SwiftCode.developer-AI-Allows-Cloud` — unlocks the SwiftCode
//     cloud model for third-party apps (gates the existing
//     `use.SwiftCodeModel` capability the same way).
//
// BINDING RULE: entitlements are stored ON the developer's API key record
// (`SDKAPIKey.entitlements`), never in the manifest, never self-asserted.
// They are granted only through the Assist access application flow
// (`SDKAssistApplicationStore.approve` → `SDKAPIKeyStore.grantEntitlement`).
// The API key token presented at call time must carry the entitlement —
// a claim in the manifest, package name, or client code is ignored.

public struct SDKEntitlement: Sendable, Hashable, RawRepresentable, Codable {
    public let rawValue: String

    /// Accepts any non-empty entitlement string. Empty strings are never valid.
    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    /// Internal non-failable initializer for the known v1 constants.
    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    /// Unlocks the Assist SDK variants (`assistSDK.UI` / `assistSDK`) for
    /// the developer's app. Granted through the Assist access application
    /// flow only.
    public static let developerAIAssist = SDKEntitlement(unchecked: "com.SwiftCode.developer-AI-Assist")

    /// Unlocks the SwiftCode cloud model for third-party apps. Granted
    /// through the Assist access application flow only (for applications
    /// that declare third-party/off-device model usage).
    public static let developerAIAllowsCloud = SDKEntitlement(unchecked: "com.SwiftCode.developer-AI-Allows-Cloud")

    // MARK: Codable (single-value: the bare entitlement string)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let entitlement = SDKEntitlement(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Developer API key entitlement must be a non-empty string."
            )
        }
        self = entitlement
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
