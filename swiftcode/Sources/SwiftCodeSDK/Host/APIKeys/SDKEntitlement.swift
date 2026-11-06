import Foundation

// MARK: - SDKEntitlement
//
// Ported from Legacy `SwiftCode/SDK/Host/APIKeys/SDKEntitlement.swift`
// (Dylan's own code; direct port authorised under MIT).
// Deferred from Wave 13 — ported here.
//
// Key-bound entitlements: grants that live on a verified developer API
// key, never on a manifest and never self-asserted by an extension.
// The broker and the Assist gate read ONLY the verified key record.

/// An entitlement bound to a verified developer API key.
///
/// Open `RawRepresentable`: the two known values below are the current
/// set, but any non-empty string round-trips so future entitlements do
/// not break decoding of stored key records.
public struct SDKEntitlement: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Unlocks the Assist SDK variants (`assist.ui` / `assist.headless` /
    /// `assist.main`) for the key holder's extensions.
    public static let developerAIAssist = SDKEntitlement("com.SwiftCode.developer-AI-Assist")
    /// Unlocks the SwiftCode Cloud Model for the key holder's extensions.
    public static let developerAIAllowsCloud = SDKEntitlement("com.SwiftCode.developer-AI-Allows-Cloud")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Entitlement must not be empty.")
        }
        self.rawValue = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
