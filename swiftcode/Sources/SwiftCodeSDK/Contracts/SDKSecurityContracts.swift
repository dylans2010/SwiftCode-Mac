import Foundation

// MARK: - SDK Security IPC contracts
//
// Wire contracts for the `security.*` IPC methods (spec §8.1: `use.Security`,
// high risk — host-mediated Keychain secrets the extension never sees).
//
// These types are the exact shapes the TypeScript `SecurityAPI`
// (`TypeScript/package/src/security.ts`) sends and asserts on:
//   security.addValue     {"securityID","valueID","label?","prompt?"}
//                         → {"valueID","created"}
//   security.hasValue     {"securityID","valueID"} → {"hasValue"}
//   security.listValueIDs {"securityID"}
//                         → {"values":[{"valueID","label","createdAt"}]}
//   security.deleteValue  {"securityID","valueID"} → null
//   security.useValue     {"securityID","valueID","operation"}
//                         → {"status","body"}
//
// SECURITY INVARIANT — read before touching: no type here carries secret
// bytes, in either direction. `securityID` is the app's Security ID (the
// *kind* of secret, e.g. "api-keys"); `valueID` names the user's slot
// (e.g. "github-token"). The Keychain partition's extension component is
// derived host-side from the session-bound caller identity by
// `SDKSecurityService` — never from these payloads. A secret in transit to
// the extension is a contract violation.
//
// Decoding is tolerant the same way `SDKSandboxRunRequest` is: required
// fields decode strictly, optional fields fall back to host defaults, and a
// present-but-wrongly-typed field fails decoding (→ `.invalidArgument` at
// the dispatcher).

// MARK: - Requests

/// `security.addValue` — ask the host to present its secure prompt and store
/// the entered secret under (`securityID`, `valueID`). The extension never
/// supplies (or sees) the secret itself.
public struct SDKSecurityAddRequest: Codable, Sendable {
    /// The app's Security ID — the *kind* of secret (e.g. "api-keys").
    /// Host-bound to the caller's extension namespace by the service; the
    /// raw payload value never addresses the Keychain directly.
    public let securityID: String
    /// The user's named slot for this kind of secret (e.g. "github-token").
    public let valueID: String
    /// Human label shown in the host's secure prompt and in listings.
    public let label: String?
    /// One-line explanation shown in the prompt of what the secret is for.
    public let prompt: String?

    public init(securityID: String, valueID: String, label: String? = nil, prompt: String? = nil) {
        self.securityID = securityID
        self.valueID = valueID
        self.label = label
        self.prompt = prompt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
        valueID = try container.decode(String.self, forKey: .valueID)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
    }
}

/// `security.hasValue` / `security.deleteValue` — existence check or deletion
/// of one stored value. Metadata only; the secret is never returned.
public struct SDKSecurityLookupRequest: Codable, Sendable {
    public let securityID: String
    public let valueID: String

    public init(securityID: String, valueID: String) {
        self.securityID = securityID
        self.valueID = valueID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
        valueID = try container.decode(String.self, forKey: .valueID)
    }
}

/// `security.listValueIDs` — inventory of one app Security ID. Names and
/// metadata only; values stay in the Keychain.
public struct SDKSecurityListRequest: Codable, Sendable {
    public let securityID: String

    public init(securityID: String) {
        self.securityID = securityID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
    }
}

/// `security.useValue` — ask the host to inject the stored secret into one
/// approved host operation and perform it. The only operation kind in this
/// release is `httpAuthorization`: the host attaches the secret as the
/// `Authorization` header and performs the HTTPS request itself.
public struct SDKSecurityUseRequest: Codable, Sendable {
    public let securityID: String
    public let valueID: String
    public let operation: SDKSecurityUseOperation

    public init(securityID: String, valueID: String, operation: SDKSecurityUseOperation) {
        self.securityID = securityID
        self.valueID = valueID
        self.operation = operation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        securityID = try container.decode(String.self, forKey: .securityID)
        valueID = try container.decode(String.self, forKey: .valueID)
        operation = try container.decode(SDKSecurityUseOperation.self, forKey: .operation)
    }
}

/// One host-mediated use of a stored secret. `kind` is validated by the
/// service — unknown kinds are `.invalidArgument`, never improvised.
public struct SDKSecurityUseOperation: Codable, Sendable {
    /// The only supported kind in this release: `"httpAuthorization"`.
    public let kind: String
    public let request: SDKSecurityHTTPRequest

    public init(kind: String, request: SDKSecurityHTTPRequest) {
        self.kind = kind
        self.request = request
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        request = try container.decode(SDKSecurityHTTPRequest.self, forKey: .request)
    }
}

/// The HTTPS request the host performs with the secret attached as the
/// `Authorization` header. The extension must NOT supply `Authorization`
/// itself — the host owns that header and rejects a client-supplied one.
public struct SDKSecurityHTTPRequest: Codable, Sendable {
    /// Bare HTTP method token (e.g. "GET", "POST"). Validated host-side.
    public let method: String
    /// Absolute HTTPS URL. No embedded credentials; https only.
    public let url: String
    /// Extra headers. Must not contain `Authorization` (any casing).
    public let headers: [String: String]?
    /// Optional request body (string). Size-bounded by the service.
    public let body: String?

    public init(method: String, url: String, headers: [String: String]? = nil, body: String? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decode(String.self, forKey: .method)
        url = try container.decode(String.self, forKey: .url)
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
        body = try container.decodeIfPresent(String.self, forKey: .body)
    }
}

// MARK: - Responses

/// `security.addValue` result — metadata only. `created` is false when the
/// call replaced an existing value.
public struct SDKSecurityAddedValue: Codable, Sendable {
    public let valueID: String
    public let created: Bool

    public init(valueID: String, created: Bool) {
        self.valueID = valueID
        self.created = created
    }
}

/// `security.hasValue` result — existence only, never the secret.
public struct SDKSecurityHasValue: Codable, Sendable {
    public let hasValue: Bool

    public init(hasValue: Bool) {
        self.hasValue = hasValue
    }
}

/// One entry of a `security.listValueIDs` result. Carries NO secret
/// material — safe to hand to the extension. `label` is always present
/// (empty when none was stored); `createdAt` is ISO-8601.
public struct SDKSecurityStoredValue: Codable, Sendable {
    public let valueID: String
    public let label: String
    public let createdAt: String

    public init(valueID: String, label: String, createdAt: String) {
        self.valueID = valueID
        self.label = label
        self.createdAt = createdAt
    }
}

/// `security.listValueIDs` result — names and metadata, never values.
public struct SDKSecurityValueList: Codable, Sendable {
    public let values: [SDKSecurityStoredValue]

    public init(values: [SDKSecurityStoredValue]) {
        self.values = values
    }
}

/// `security.useValue` result — the operation's outcome only. The secret
/// NEVER appears here.
public struct SDKSecurityHTTPResponse: Codable, Sendable {
    public let status: Int
    public let body: String

    public init(status: Int, body: String) {
        self.status = status
        self.body = body
    }
}
