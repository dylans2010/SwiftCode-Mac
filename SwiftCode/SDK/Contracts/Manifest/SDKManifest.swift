import Foundation

// MARK: - SDKManifestJSONValue
//
// Lossless representation of arbitrary JSON values so `SDKManifest` can
// preserve unknown top-level fields during visual editing and re-serialization
// without stripping custom or forward-compatible keys.

public indirect enum SDKManifestJSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: SDKManifestJSONValue])
    case array([SDKManifestJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let obj = try? container.decode([String: SDKManifestJSONValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([SDKManifestJSONValue].self) {
            self = .array(arr)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value in SDKManifest."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    public var summaryDescription: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .int(let i): return "\(i)"
        case .double(let d): return "\(d)"
        case .bool(let b): return b ? "true" : "false"
        case .object(let o): return "{\(o.count) keys}"
        case .array(let a): return "[\(a.count) items]"
        case .null: return "null"
        }
    }
}

// MARK: - SDKManifest
//
// Versioned extension manifest (manifestVersion 1), per Docs/Intro-to-SDK.md
// §7.1. Decoded from `swiftcode.json` at an extension package root.

public struct SDKManifest: Codable, Equatable, Hashable, Sendable {
    public var manifestVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var type: String
    public var runtime: SDKManifestRuntime
    public var sdk: SDKManifestSDKRef
    public var capabilities: [SDKManifestCapability]
    public var contributes: SDKManifestContributions?
    /// Descriptive metadata only (spec §9.1, ADR §9): `requested: true` does
    /// NOT grant Assist access — the broker denies it independently.
    /// Absent from the JSON → `requested: false`.
    public var assist: SDKManifestAssist
    /// Preserves any unrecognized top-level JSON fields so visual editing
    /// never destroys custom or forward-compatible manifest properties.
    public var unknownFields: [String: SDKManifestJSONValue]

    public init(
        manifestVersion: Int = 1,
        id: String,
        name: String,
        version: String,
        description: String? = nil,
        type: String = "extension",
        runtime: SDKManifestRuntime,
        sdk: SDKManifestSDKRef,
        capabilities: [SDKManifestCapability],
        contributes: SDKManifestContributions? = nil,
        assist: SDKManifestAssist = SDKManifestAssist(requested: false),
        unknownFields: [String: SDKManifestJSONValue] = [:]
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
        self.unknownFields = unknownFields
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
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

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private static let knownKeyNames: Set<String> = Set(CodingKeys.allCases.map(\.rawValue))

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
        if container.contains(.assist) {
            assist = try container.decode(SDKManifestAssist.self, forKey: .assist)
        } else {
            assist = SDKManifestAssist(requested: false)
        }

        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var extras: [String: SDKManifestJSONValue] = [:]
        for key in dynamicContainer.allKeys where !Self.knownKeyNames.contains(key.stringValue) {
            if let val = try? dynamicContainer.decode(SDKManifestJSONValue.self, forKey: key) {
                extras[key.stringValue] = val
            }
        }
        unknownFields = extras
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manifestVersion, forKey: .manifestVersion)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(type, forKey: .type)
        try container.encode(runtime, forKey: .runtime)
        try container.encode(sdk, forKey: .sdk)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encodeIfPresent(contributes, forKey: .contributes)
        try container.encode(assist, forKey: .assist)

        if !unknownFields.isEmpty {
            var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            for (k, v) in unknownFields where !Self.knownKeyNames.contains(k) {
                if let dk = DynamicCodingKey(stringValue: k) {
                    try dynamicContainer.encode(v, forKey: dk)
                }
            }
        }
    }

    /// Serializes the manifest to deterministic, pretty-printed UTF-8 JSON bytes
    /// with a trailing newline, preserving any `unknownFields`.
    public func encodedPrettyJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        if data.last != UInt8(ascii: "\n") {
            data.append(UInt8(ascii: "\n"))
        }
        return data
    }

    /// Serializes the manifest to a formatted JSON string.
    public func encodedPrettyString() throws -> String {
        let data = try encodedPrettyJSON()
        return String(data: data, encoding: .utf8) ?? "{}\n"
    }
}

// MARK: - SDKManifestRuntime

public struct SDKManifestRuntime: Codable, Equatable, Hashable, Sendable {
    /// v1 supports `typescript` only.
    public var language: String
    /// Relative path (inside the package) to the runtime entry file.
    public var entrypoint: String
    public var minimumSwiftCodeVersion: String

    public init(language: String = "typescript", entrypoint: String = "dist/index.js", minimumSwiftCodeVersion: String = "1.0.0") {
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

public struct SDKManifestSDKRef: Codable, Equatable, Hashable, Sendable {
    /// Must be `@swiftcode/sdk`.
    public var name: String
    /// Semver range the extension supports (v1 whitelist, see validator).
    public var versionRange: String
    /// Host/runtime IPC contract version. Must equal 1.
    public var protocolVersion: Int

    public init(name: String = "@swiftcode/sdk", versionRange: String = "1.2.0", protocolVersion: Int = 1) {
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

public struct SDKManifestCapability: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// One of the canonical capability IDs (`SDKCapability.all`).
    public var id: String
    /// Plain-language justification for the capability request.
    public var reason: String

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

public struct SDKManifestCommandContribution: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Lowercase kebab-case command identifier, unique within the manifest.
    public var id: String
    /// Human-readable command title.
    public var title: String

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

public struct SDKManifestContributions: Codable, Equatable, Hashable, Sendable {
    public var commands: [SDKManifestCommandContribution]

    public init(commands: [SDKManifestCommandContribution]) {
        self.commands = commands
    }

    private enum CodingKeys: String, CodingKey {
        case commands
    }
}

// MARK: - SDKManifestAssist

public struct SDKManifestAssist: Codable, Equatable, Hashable, Sendable {
    /// Descriptive metadata only. Never interpreted as a grant (ADR §9).
    public var requested: Bool

    public init(requested: Bool) {
        self.requested = requested
    }

    private enum CodingKeys: String, CodingKey {
        case requested
    }
}
