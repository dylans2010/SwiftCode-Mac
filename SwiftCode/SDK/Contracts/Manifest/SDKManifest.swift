import Foundation

// MARK: - SDKManifest
//
// Versioned extension manifest (manifestVersion 1), per Docs/Intro-to-SDK.md
// §7.1. Decoded from `swiftcode.json` at an extension package root.
//
// DATA ONLY: no validation lives here. Structural and semantic validation is
// performed by `SDKManifestValidator` (Host/ExtensionRegistry); package-level
// checks (entrypoint existence, traversal, executables) by
// `SDKPackageValidator`. A successfully validated manifest is a *request* to
// the host — it grants nothing (spec §7.2).

public struct SDKManifest: Codable, Sendable {
    public let manifestVersion: Int
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let type: String
    public let runtime: SDKManifestRuntime
    public let sdk: SDKManifestSDKRef
    public let capabilities: [SDKManifestCapability]
    public let contributes: SDKManifestContributions?
    /// Descriptive metadata only (spec §9.1, ADR §9): `requested: true` does
    /// NOT grant Assist access — the broker denies it independently.
    /// Absent from the JSON → `requested: false`.
    public let assist: SDKManifestAssist

    public init(
        manifestVersion: Int,
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        type: String = "extension",
        runtime: SDKManifestRuntime,
        sdk: SDKManifestSDKRef,
        capabilities: [SDKManifestCapability],
        contributes: SDKManifestContributions? = nil,
        assist: SDKManifestAssist = SDKManifestAssist(requested: false)
    ) {
        self.manifestVersion = manifestVersion
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.type = type
        self.runtime = runtime
        self.sdk = sdk
        self.capabilities = capabilities
        self.contributes = contributes
        self.assist = assist
    }

    private enum CodingKeys: String, CodingKey {
        case manifestVersion
        case id
        case name
        case version
        case description
        case type
        case runtime
        case sdk
        case capabilities
        case contributes
        case assist
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decode(String.self, forKey: .type)
        runtime = try container.decode(SDKManifestRuntime.self, forKey: .runtime)
        sdk = try container.decode(SDKManifestSDKRef.self, forKey: .sdk)
        capabilities = try container.decode([SDKManifestCapability].self, forKey: .capabilities)
        contributes = try container.decodeIfPresent(SDKManifestContributions.self, forKey: .contributes)
        // Absent `assist` → requested: false. A *present* but malformed
        // `assist` must still fail decoding (never silently defaulted).
        if container.contains(.assist) {
            assist = try container.decode(SDKManifestAssist.self, forKey: .assist)
        } else {
            assist = SDKManifestAssist(requested: false)
        }
    }
}

// MARK: - SDKManifestRuntime

public struct SDKManifestRuntime: Codable, Sendable {
    /// v1 supports `typescript` only.
    public let language: String
    /// Relative path (inside the package) to the runtime entry file.
    public let entrypoint: String
    public let minimumSwiftCodeVersion: String

    public init(language: String, entrypoint: String, minimumSwiftCodeVersion: String) {
        self.language = language
        self.entrypoint = entrypoint
        self.minimumSwiftCodeVersion = minimumSwiftCodeVersion
    }

    private enum CodingKeys: String, CodingKey {
        case language
        case entrypoint
        case minimumSwiftCodeVersion
    }
}

// MARK: - SDKManifestSDKRef

public struct SDKManifestSDKRef: Codable, Sendable {
    /// Must be `@swiftcode/sdk`.
    public let name: String
    /// Semver range the extension supports (v1 whitelist, see validator).
    public let versionRange: String
    /// Host/runtime IPC contract version. Must equal 1.
    public let protocolVersion: Int

    public init(name: String, versionRange: String, protocolVersion: Int) {
        self.name = name
        self.versionRange = versionRange
        self.protocolVersion = protocolVersion
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case versionRange
        case protocolVersion
    }
}

// MARK: - SDKManifestCapability

public struct SDKManifestCapability: Codable, Sendable {
    /// One of the fixed v1 capability IDs (ADR §7).
    public let id: String
    /// Plain-language justification for the capability request.
    public let reason: String

    public init(id: String, reason: String) {
        self.id = id
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case reason
    }
}

// MARK: - SDKManifestCommandContribution

public struct SDKManifestCommandContribution: Codable, Sendable {
    /// Lowercase kebab-case command identifier, unique within the manifest.
    public let id: String
    /// Human-readable command title.
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
    }
}

// MARK: - SDKManifestContributions

public struct SDKManifestContributions: Codable, Sendable {
    public let commands: [SDKManifestCommandContribution]

    public init(commands: [SDKManifestCommandContribution]) {
        self.commands = commands
    }

    private enum CodingKeys: String, CodingKey {
        case commands
    }
}

// MARK: - SDKManifestAssist

public struct SDKManifestAssist: Codable, Sendable {
    /// Descriptive metadata only. Never interpreted as a grant (ADR §9).
    public let requested: Bool

    public init(requested: Bool) {
        self.requested = requested
    }

    private enum CodingKeys: String, CodingKey {
        case requested
    }
}
