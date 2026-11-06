import Foundation

// MARK: - swiftcode.json model (spec §2.2)

public struct ManifestRuntime: Codable, Equatable, Hashable, Sendable {
    public var language: String
    public var entrypoint: String
    public var minimumSwiftCodeVersion: String

    public init(language: String = "typescript", entrypoint: String = "dist/index.js",
                minimumSwiftCodeVersion: String = "1.0.0") {
        self.language = language
        self.entrypoint = entrypoint
        self.minimumSwiftCodeVersion = minimumSwiftCodeVersion
    }
}

public struct ManifestSDKRef: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var versionRange: String
    public var protocolVersion: Int

    public init(name: String = "@swiftcode/sdk", versionRange: String = "^1.0.0", protocolVersion: Int = 1) {
        self.name = name
        self.versionRange = versionRange
        self.protocolVersion = protocolVersion
    }
}

public struct ManifestCapability: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var reason: String

    public init(id: String, reason: String) {
        self.id = id
        self.reason = reason
    }
}

public struct ManifestCommand: Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct ManifestContributions: Codable, Equatable, Hashable, Sendable {
    public var commands: [ManifestCommand]

    public init(commands: [ManifestCommand] = []) {
        self.commands = commands
    }
}

public struct ManifestAssist: Codable, Equatable, Hashable, Sendable {
    public var requested: Bool

    public init(requested: Bool = false) {
        self.requested = requested
    }
}

/// One struct for `swiftcode.json`, with the strict validator's
/// expectations and the `"^1.0.0"` range default (the documented
/// authoring default). Unknown top-level keys are preserved in
/// `unknownFields` so visual editing never destroys them.
public struct SwiftCodeManifest: Codable, Equatable, Hashable, Sendable {
    public var manifestVersion: Int
    public var id: String
    public var name: String
    public var version: String
    public var description: String?
    public var type: String
    public var runtime: ManifestRuntime
    public var sdk: ManifestSDKRef
    public var capabilities: [ManifestCapability]
    public var contributes: ManifestContributions?
    public var assist: ManifestAssist
    public var unknownFields: [String: JSONValue]

    public init(manifestVersion: Int = 1, id: String, name: String, version: String,
                description: String? = nil, type: String = "extension",
                runtime: ManifestRuntime = ManifestRuntime(), sdk: ManifestSDKRef = ManifestSDKRef(),
                capabilities: [ManifestCapability] = [], contributes: ManifestContributions? = nil,
                assist: ManifestAssist = ManifestAssist(), unknownFields: [String: JSONValue] = [:]) {
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

    enum CodingKeys: String, CodingKey, CaseIterable {
        case manifestVersion, id, name, version, description, type, runtime, sdk,
             capabilities, contributes, assist
    }

    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decodeIfPresent(Int.self, forKey: .manifestVersion) ?? 1
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "extension"
        runtime = try container.decodeIfPresent(ManifestRuntime.self, forKey: .runtime) ?? ManifestRuntime()
        sdk = try container.decodeIfPresent(ManifestSDKRef.self, forKey: .sdk) ?? ManifestSDKRef()
        capabilities = try container.decodeIfPresent([ManifestCapability].self, forKey: .capabilities) ?? []
        contributes = try container.decodeIfPresent(ManifestContributions.self, forKey: .contributes)
        assist = try container.decodeIfPresent(ManifestAssist.self, forKey: .assist) ?? ManifestAssist()
        var unknown: [String: JSONValue] = [:]
        let anyContainer = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map { $0.rawValue })
        for key in anyContainer.allKeys where !known.contains(key.stringValue) {
            unknown[key.stringValue] = try anyContainer.decode(JSONValue.self, forKey: key)
        }
        unknownFields = unknown
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
        var anyContainer = encoder.container(keyedBy: AnyKey.self)
        for (key, value) in unknownFields {
            guard let codingKey = AnyKey(stringValue: key) else { continue }
            try anyContainer.encode(value, forKey: codingKey)
        }
    }
}

public struct ManifestDiagnostic: Identifiable, Equatable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable { case error, warning, info }
    public let id: String
    public let severity: Severity
    public let field: String
    public let message: String
    public let suggestion: String
    public let line: Int?

    public init(severity: Severity, field: String, message: String, suggestion: String, line: Int? = nil) {
        self.id = "\(field):\(message)"
        self.severity = severity
        self.field = field
        self.message = message
        self.suggestion = suggestion
        self.line = line
    }
}

// MARK: - Strict validator (spec §2.3)

/// The strict `SDKManifestValidator` as the install-time gate. The
/// lenient `ExtensionValidator` is NOT reimplemented (spec §2.3).
public enum SwiftCodeManifestValidator {
    public static let maxManifestBytes = 64 * 1024
    public static let hostSDKVersion = "1.2.0"

    /// 35 SDK ids + 6 `use.Security.*` method scopes (spec §5.1).
    public static var supportedCapabilities: Set<String> {
        Set(SDKCapabilityID.allCases.map { $0.rawValue }).union([
            "use.Security.keychain", "use.Security.audit", "use.Security.crypto",
            "use.Security.securePrompt", "use.Security.redaction", "use.Security.policy",
        ])
    }

    private static let idPattern = "^[a-z0-9]+(\\.[a-z0-9-]+)+$"
    private static let versionPattern = #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#
    private static let commandPattern = "^[a-z][a-z0-9.-]{0,63}$"

    static func matches(_ string: String, pattern: String) -> Bool {
        string.range(of: pattern, options: .regularExpression) != nil
    }

    /// Throws `YcodeExtensionError.manifest` when any error-severity
    /// diagnostic is produced.
    public static func validate(data: Data) throws -> SwiftCodeManifest {
        if data.count > maxManifestBytes {
            throw YcodeExtensionError.manifest(
                "Manifest exceeds the 64 KiB limit (resourceLimitExceeded).")
        }
        let diagnostics = validateWithDiagnostics(data: data)
        if let firstError = diagnostics.first(where: { $0.severity == .error }) {
            throw YcodeExtensionError.manifest(firstError.message)
        }
        do {
            return try JSONDecoder().decode(SwiftCodeManifest.self, from: data)
        } catch {
            throw YcodeExtensionError.manifest("Manifest could not be decoded: \(error.localizedDescription)")
        }
    }

    public static func validateWithDiagnostics(data: Data, projectRoot: URL? = nil,
                                               grantedCapabilities: Set<String>? = nil) -> [ManifestDiagnostic] {
        var diagnostics: [ManifestDiagnostic] = []
        let text = String(decoding: data, as: UTF8.self)
        func line(for field: String) -> Int? {
            // Line numbers located by text search (spec §2.3).
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, line) in lines.enumerated() where line.contains("\"\(field)\"") {
                return index + 1
            }
            return nil
        }
        func error(_ field: String, _ message: String, _ suggestion: String) {
            diagnostics.append(ManifestDiagnostic(severity: .error, field: field, message: message,
                                                  suggestion: suggestion, line: line(for: field)))
        }
        func warning(_ field: String, _ message: String, _ suggestion: String) {
            diagnostics.append(ManifestDiagnostic(severity: .warning, field: field, message: message,
                                                  suggestion: suggestion, line: line(for: field)))
        }
        if data.count > maxManifestBytes {
            error("manifest", "Manifest exceeds the 64 KiB limit.", "Split the manifest or shorten descriptions.")
            return diagnostics
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            error("manifest", "Manifest is not valid JSON.", "Fix the JSON syntax.")
            return diagnostics
        }
        // Missing required keys.
        for key in ["manifestVersion", "id", "name", "version", "type", "runtime", "sdk", "capabilities"] {
            if object[key] == nil {
                error(key, "Missing required field '\(key)'.", "Add '\(key)' to the manifest.")
            }
        }
        if let version = object["manifestVersion"] as? Int {
            if version != 1 { error("manifestVersion", "Unsupported manifestVersion \(version); expected 1.", "Set manifestVersion to 1.") }
        } else if object["manifestVersion"] != nil {
            error("manifestVersion", "manifestVersion must be the integer 1.", "Set manifestVersion to 1.")
        }
        if let id = object["id"] as? String {
            if id.count > 128 { error("id", "id exceeds 128 characters.", "Shorten the id.") }
            if !matches(id, pattern: idPattern) {
                error("id", "id must be a lowercase reverse-DNS identifier.", "Use an id like com.example.my-extension.")
            }
        } else if object["id"] != nil {
            error("id", "id must be a string.", "Use a lowercase reverse-DNS string id.")
        }
        if let name = object["name"] as? String {
            if name.trimmingCharacters(in: .whitespaces).isEmpty { error("name", "name must not be blank.", "Provide a display name.") }
            if name.count > 128 { error("name", "name exceeds 128 characters.", "Shorten the name.") }
        }
        if let version = object["version"] as? String {
            if version.count > 32 { error("version", "version exceeds 32 characters.", "Shorten the version.") }
            if !matches(version, pattern: versionPattern) {
                error("version", "version must be semver (major.minor.patch, prerelease suffix allowed).", "Use a version like 1.0.0.")
            }
        }
        if let description = object["description"] as? String, description.count > 1024 {
            error("description", "description exceeds 1024 characters.", "Shorten the description.")
        }
        if let type = object["type"] as? String, type != "extension" && type != "application" {
            error("type", "type must be \"extension\" or \"application\".", "Set type to \"extension\".")
        }
        if let runtime = object["runtime"] as? [String: Any] {
            if let language = runtime["language"] as? String, language != "typescript" {
                error("runtime.language", "runtime.language must be \"typescript\".", "Set runtime.language to \"typescript\".")
            }
            if let entrypoint = runtime["entrypoint"] as? String {
                if entrypoint.isEmpty { error("runtime.entrypoint", "runtime.entrypoint must not be blank.", "Set an entrypoint such as dist/index.js.") }
                if entrypoint.count > 512 { error("runtime.entrypoint", "runtime.entrypoint exceeds 512 characters.", "Shorten the entrypoint path.") }
                if entrypoint.hasPrefix("/") || entrypoint.split(separator: "/").contains("..") {
                    error("runtime.entrypoint", "runtime.entrypoint must be a relative path inside the package (pathTraversal).", "Use a relative path with no '..' segments.")
                } else if entrypoint.split(separator: "/", omittingEmptySubsequences: false).contains("") {
                    error("runtime.entrypoint", "runtime.entrypoint must not contain empty segments.", "Remove empty path segments.")
                } else if let root = projectRoot {
                    let candidate = root.appendingPathComponent(entrypoint).standardized
                    if !FileManager.default.fileExists(atPath: candidate.path) {
                        error("runtime.entrypoint", "Entrypoint file does not exist in the package.", "Ship the entrypoint file at \(entrypoint).")
                    }
                }
            }
            if let minimum = runtime["minimumSwiftCodeVersion"] as? String,
               !matches(minimum, pattern: versionPattern) {
                error("runtime.minimumSwiftCodeVersion", "minimumSwiftCodeVersion must be valid semver.", "Use a version like 1.0.0.")
            }
        }
        if let sdk = object["sdk"] as? [String: Any] {
            if let name = sdk["name"] as? String, name != "@swiftcode/sdk" {
                error("sdk.name", "sdk.name must be \"@swiftcode/sdk\".", "Set sdk.name to \"@swiftcode/sdk\".")
            }
            if let range = sdk["versionRange"] as? String, !isSDKRangeCompatible(range) {
                error("sdk.versionRange", "sdk.versionRange '\(range)' does not admit the host SDK \(hostSDKVersion).",
                      "Use an exact 1.x version, ^1.x.0, ~1.x.0, or >=1.x.0 <2.0.0.")
            }
            if let protocolVersion = sdk["protocolVersion"] as? Int, protocolVersion != 1 {
                error("sdk.protocolVersion", "sdk.protocolVersion must be 1.", "Set sdk.protocolVersion to 1.")
            } else if sdk["protocolVersion"] != nil && !(sdk["protocolVersion"] is Int) {
                error("sdk.protocolVersion", "sdk.protocolVersion must be the integer 1.", "Set sdk.protocolVersion to 1.")
            }
        }
        if let capabilities = object["capabilities"] as? [[String: Any]] {
            if capabilities.count > 32 {
                error("capabilities", "capabilities exceeds 32 entries.", "Declare at most 32 capabilities.")
            }
            var seen: Set<String> = []
            for capability in capabilities {
                guard let id = capability["id"] as? String else {
                    error("capabilities", "A capability entry is missing 'id'.", "Add an id to every capability.")
                    continue
                }
                if !supportedCapabilities.contains(id) {
                    error("capabilities", "Unknown capability id '\(id)'.", "Use a capability id from the SDK registry.")
                }
                if !seen.insert(id).inserted {
                    error("capabilities", "Duplicate capability id '\(id)'.", "Declare each capability once.")
                }
                if let reason = capability["reason"] as? String {
                    if reason.trimmingCharacters(in: .whitespaces).isEmpty {
                        error("capabilities", "Capability '\(id)' has a blank reason.", "Explain why the capability is needed.")
                    } else if reason.count > 512 {
                        error("capabilities", "Capability '\(id)' reason exceeds 512 characters.", "Shorten the reason.")
                    }
                } else {
                    error("capabilities", "Capability '\(id)' is missing a reason.", "Add a reason for the capability.")
                }
                if let granted = grantedCapabilities, !granted.contains(id) {
                    // Diagnostic-only: this never grants anything.
                    warning("capabilities", "Capability '\(id)' is declared but not granted.", "Grant it in Extensions > Permissions.")
                }
            }
        }
        if let contributes = object["contributes"] as? [String: Any],
           let commands = contributes["commands"] as? [[String: Any]] {
            if commands.count > 64 {
                error("contributes.commands", "commands exceeds 64 entries.", "Declare at most 64 commands.")
            }
            var seen: Set<String> = []
            for command in commands {
                guard let id = command["id"] as? String else {
                    error("contributes.commands", "A command is missing 'id'.", "Add an id to every command.")
                    continue
                }
                if id.count > 64 || !matches(id, pattern: commandPattern) {
                    error("contributes.commands", "Command id '\(id)' must be lowercase kebab-case starting with a letter (max 64 chars).", "Use an id like run-build.")
                }
                if !seen.insert(id).inserted {
                    error("contributes.commands", "Duplicate command id '\(id)'.", "Declare each command once.")
                }
                if let title = command["title"] as? String {
                    if title.trimmingCharacters(in: .whitespaces).isEmpty {
                        error("contributes.commands", "Command '\(id)' has a blank title.", "Provide a title.")
                    } else if title.count > 128 {
                        error("contributes.commands", "Command '\(id)' title exceeds 128 characters.", "Shorten the title.")
                    }
                } else {
                    error("contributes.commands", "Command '\(id)' is missing a title.", "Add a title.")
                }
            }
        }
        return diagnostics
    }

    /// SDK range whitelist for host SDK 1.2.0: exact `1.0.0` / `1.1.0` /
    /// `1.2.0`, `^1.x.0`, `~1.x.0`, `>=1.x.0 <2.0.0`.
    public static func isSDKRangeCompatible(_ range: String) -> Bool {
        let trimmed = range.trimmingCharacters(in: .whitespaces)
        if ["1.0.0", "1.1.0", "1.2.0"].contains(trimmed) { return true }
        if trimmed.hasPrefix("^") || trimmed.hasPrefix("~") {
            // Whitelist form is ^1.x.0 / ~1.x.0 with x in 0...2 and patch 0.
            guard let version = SemanticVersion(string: String(trimmed.dropFirst())) else { return false }
            return version.major == 1 && version.minor <= 2 && version.patch == 0
        }
        if trimmed.hasPrefix(">=") {
            // ">=1.x.0 <2.0.0" (the space-separated upper bound is optional in practice).
            let lower = String(trimmed.dropFirst(2)).split(separator: " ").first.map(String.init) ?? ""
            guard let version = SemanticVersion(string: lower) else { return false }
            return version.major == 1
        }
        return false
    }
}
