import Foundation

// MARK: - SDKManifestDiagnostic
//
// Structured diagnostic item produced by `SDKManifestValidator.validateWithDiagnostics`
// for the Studio Visual Manifest Editor and the Studio Compiler Diagnostics panel.

public struct SDKManifestDiagnostic: Identifiable, Equatable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case error
        case warning
        case info
    }

    public let id: String
    public let severity: Severity
    public let field: String
    public let message: String
    public let suggestion: String
    public let line: Int?

    public init(
        id: String? = nil,
        severity: Severity,
        field: String,
        message: String,
        suggestion: String,
        line: Int? = nil
    ) {
        self.id = id ?? "\(severity.rawValue):\(field):\(message)"
        self.severity = severity
        self.field = field
        self.message = message
        self.suggestion = suggestion
        self.line = line
    }
}

// MARK: - SDKManifestValidator
//
// Strict manifest validation for `swiftcode.json` (spec §7.2, §7.3).
// `validate(data:)` performs pure validation on manifest bytes.
// `validateWithDiagnostics(data:projectRoot:grantedCapabilities:)` collects
// all syntactic, semantic, project-structure, and authorization diagnostics
// for the Studio Visual Manifest Editor and Compiler Pipeline.

public enum SDKManifestValidator {

    // MARK: - Limits

    /// Manifests larger than this are rejected before parsing.
    private static let maxManifestBytes = 64 * 1024
    private static let supportedManifestVersion = 1
    private static let supportedProtocolVersion = 1
    private static let requiredSDKName = "@swiftcode/sdk"
    /// Host SDK version this validator checks compatibility against
    /// (additive release 1.2.0: compatible with 1.0.0, 1.1.0, and 1.2.0).
    private static let hostSDKVersion = (major: 1, minor: 2, patch: 0)

    private static let maxIDLength = 128
    private static let maxNameLength = 128
    private static let maxVersionLength = 32
    private static let maxDescriptionLength = 1024
    private static let maxReasonLength = 512
    private static let maxCommandTitleLength = 128
    private static let maxEntrypointLength = 512
    private static let maxCapabilities = 32
    private static let maxCommands = 64

    /// The canonical capability registry (`SDKCapabilityRegistry.all` + sub-scopes in `ScopesIDLists.all`).
    /// Unknown IDs are rejected — never silently reinterpreted as a known capability (spec §7.3).
    public static var supportedCapabilities: Set<String> {
        var ids = Set(SDKCapabilityRegistry.all.map(\.id.rawValue))
        ids.formUnion(ScopesIDLists.all.map(\.id))
        return ids
    }

    // MARK: - Entry point

    /// Validates manifest bytes and returns the decoded manifest.
    /// - Throws: `SDKError` on every rejection path.
    public static func validate(data: Data) throws -> SDKManifest {
        guard data.count <= maxManifestBytes else {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "The extension manifest exceeds the 64 KB size limit.",
                suggestion: "Reduce swiftcode.json to 64 KB or less and try again."
            )
        }

        // 1. Malformed JSON.
        let topLevel: Any
        do {
            topLevel = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SDKError(
                code: .schemaValidationFailed,
                message: "The extension manifest is not valid JSON.",
                suggestion: "Fix the JSON syntax in swiftcode.json and try again.",
                diagnostics: ["parseError": String(describing: error)]
            )
        }
        guard let object = topLevel as? [String: Any] else {
            throw SDKError(
                code: .schemaValidationFailed,
                message: "The extension manifest must be a single JSON object.",
                suggestion: "Make the top level of swiftcode.json one JSON object."
            )
        }

        // 2. Manifest version: absent/untyped → schema failure; present but
        //    unsupported → dedicated unsupported-version error.
        guard let rawVersion = object["manifestVersion"] else {
            throw SDKError(
                code: .schemaValidationFailed,
                message: "The extension manifest is missing \"manifestVersion\".",
                suggestion: "Add \"manifestVersion\": 1 to swiftcode.json."
            )
        }
        guard let manifestVersion = rawVersion as? Int else {
            throw SDKError(
                code: .schemaValidationFailed,
                message: "The extension manifest's \"manifestVersion\" must be an integer.",
                suggestion: "Set \"manifestVersion\" to 1 in swiftcode.json."
            )
        }
        guard manifestVersion == supportedManifestVersion else {
            throw SDKError(
                code: .manifestUnsupportedVersion,
                message: "Unsupported manifest version \(manifestVersion). This SwiftCode release supports manifest version 1.",
                suggestion: "Set \"manifestVersion\" to 1, or update SwiftCode to a release that supports this manifest."
            )
        }

        // 3. Typed decode: absent required fields / wrong JSON types → schema failure.
        let manifest: SDKManifest
        do {
            manifest = try JSONDecoder().decode(SDKManifest.self, from: data)
        } catch {
            throw SDKError(
                code: .schemaValidationFailed,
                message: "The extension manifest failed schema validation.",
                suggestion: "Compare swiftcode.json against the v1 manifest schema and fix the reported field.",
                diagnostics: ["decodeError": String(describing: error)]
            )
        }

        // 4. Semantic field rules.
        try validateIdentity(manifest)
        try validateRuntime(manifest.runtime)
        try validateSDKRef(manifest.sdk)
        try validateCapabilities(manifest.capabilities)
        try validateContributions(manifest.contributes)

        // `assist` is descriptive metadata only (spec §9.1, ADR §9): accepted
        // as decoded. Denial is enforced at the broker, never here.
        return manifest
    }

    // MARK: - Multi-Diagnostic Validation for Studio Editor & Compiler

    /// Collects all syntactic, semantic, project-level, and authorization diagnostics
    /// for a manifest without stopping at the first error.
    public static func validateWithDiagnostics(
        data: Data,
        projectRoot: URL? = nil,
        grantedCapabilities: Set<String>? = nil
    ) -> [SDKManifestDiagnostic] {
        var diagnostics: [SDKManifestDiagnostic] = []
        let rawText = String(data: data, encoding: .utf8) ?? ""

        if data.count > maxManifestBytes {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "swiftcode.json",
                message: "The extension manifest exceeds the 64 KB size limit (\(data.count) bytes).",
                suggestion: "Reduce swiftcode.json to 64 KB or less.",
                line: 1
            ))
            return diagnostics
        }

        let topLevel: Any
        do {
            topLevel = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            let line = extractJSONErrorLine(from: error, in: rawText)
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "swiftcode.json",
                message: "Malformed JSON syntax: \(error.localizedDescription)",
                suggestion: "Fix the JSON syntax error in swiftcode.json.",
                line: line ?? 1
            ))
            return diagnostics
        }

        guard let object = topLevel as? [String: Any] else {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "swiftcode.json",
                message: "The extension manifest must be a single JSON object.",
                suggestion: "Make the top level of swiftcode.json one JSON object.",
                line: 1
            ))
            return diagnostics
        }

        let requiredKeys = ["manifestVersion", "id", "name", "version", "type", "runtime", "sdk", "capabilities"]
        for key in requiredKeys where object[key] == nil {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: key,
                message: "Missing required field \"\(key)\".",
                suggestion: "Add \"\(key)\" to swiftcode.json.",
                line: 1
            ))
        }

        if let rawVer = object["manifestVersion"] {
            if let intVer = rawVer as? Int {
                if intVer != supportedManifestVersion {
                    diagnostics.append(SDKManifestDiagnostic(
                        severity: .error,
                        field: "manifestVersion",
                        message: "Unsupported manifestVersion \(intVer) (expected 1).",
                        suggestion: "Set \"manifestVersion\" to 1.",
                        line: findLine(ofKey: "manifestVersion", in: rawText)
                    ))
                }
            } else {
                diagnostics.append(SDKManifestDiagnostic(
                    severity: .error,
                    field: "manifestVersion",
                    message: "\"manifestVersion\" must be an integer.",
                    suggestion: "Set \"manifestVersion\": 1.",
                    line: findLine(ofKey: "manifestVersion", in: rawText)
                ))
            }
        }

        guard let manifest = try? JSONDecoder().decode(SDKManifest.self, from: data) else {
            if diagnostics.isEmpty {
                diagnostics.append(SDKManifestDiagnostic(
                    severity: .error,
                    field: "swiftcode.json",
                    message: "Manifest structure does not match the v1 schema types.",
                    suggestion: "Ensure runtime, sdk, capabilities, and contributes have the expected object/array types.",
                    line: 1
                ))
            }
            return diagnostics
        }

        // Identity checks
        let id = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.isEmpty {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "id",
                message: "Extension \"id\" must not be blank.",
                suggestion: "Set \"id\" to a reverse-DNS identifier, e.g. \"com.example.my-extension\".",
                line: findLine(ofKey: "id", in: rawText)
            ))
        } else if !matches(id, pattern: #"^[a-z0-9]+(\.[a-z0-9-]+)+$"#) {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "id",
                message: "Extension ID \"\(id)\" is not a valid lowercase reverse-DNS identifier.",
                suggestion: "Use lowercase letters, digits, and hyphens separated by dots, e.g. \"com.example.my-extension\".",
                line: findLine(ofKey: "id", in: rawText)
            ))
        }

        let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "name",
                message: "Extension \"name\" must not be blank.",
                suggestion: "Provide a human-readable display name.",
                line: findLine(ofKey: "name", in: rawText)
            ))
        }

        let version = manifest.version.trimmingCharacters(in: .whitespacesAndNewlines)
        if !matches(version, pattern: #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#) {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "version",
                message: "Version \"\(version)\" is not valid semver.",
                suggestion: "Use a semver string such as \"0.1.0\" or \"1.0.0\".",
                line: findLine(ofKey: "version", in: rawText)
            ))
        }

        if manifest.type != "extension" && manifest.type != "application" {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "type",
                message: "Unsupported manifest type \"\(manifest.type)\".",
                suggestion: "Set \"type\" to \"extension\".",
                line: findLine(ofKey: "type", in: rawText)
            ))
        }

        // Runtime checks
        if manifest.runtime.language != "typescript" {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "runtime.language",
                message: "Unsupported runtime language \"\(manifest.runtime.language)\".",
                suggestion: "Set \"runtime.language\" to \"typescript\".",
                line: findLine(ofKey: "language", in: rawText)
            ))
        }

        let ep = manifest.runtime.entrypoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if ep.isEmpty || ep.hasPrefix("/") || ep.split(separator: "/").contains("..") {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "runtime.entrypoint",
                message: "Runtime entrypoint \"\(ep)\" must be a safe relative path inside the package.",
                suggestion: "Use a relative path such as \"dist/index.js\".",
                line: findLine(ofKey: "entrypoint", in: rawText)
            ))
        } else if let root = projectRoot {
            let entryURL = root.appendingPathComponent(ep)
            let tsSourceURL = root.appendingPathComponent("src/index.ts")
            if !FileManager.default.fileExists(atPath: entryURL.path) {
                if FileManager.default.fileExists(atPath: tsSourceURL.path) {
                    diagnostics.append(SDKManifestDiagnostic(
                        severity: .info,
                        field: "runtime.entrypoint",
                        message: "Compiled entrypoint \"\(ep)\" has not been built yet (src/index.ts is present).",
                        suggestion: "Run Build in Studio to compile TypeScript sources into \(ep).",
                        line: findLine(ofKey: "entrypoint", in: rawText)
                    ))
                } else {
                    diagnostics.append(SDKManifestDiagnostic(
                        severity: .warning,
                        field: "runtime.entrypoint",
                        message: "Entrypoint \"\(ep)\" and source \"src/index.ts\" were not found in project.",
                        suggestion: "Create src/index.ts or point runtime.entrypoint to an existing file.",
                        line: findLine(ofKey: "entrypoint", in: rawText)
                    ))
                }
            }
        }

        if !matches(manifest.runtime.minimumSwiftCodeVersion, pattern: #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#) {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "runtime.minimumSwiftCodeVersion",
                message: "minimumSwiftCodeVersion \"\(manifest.runtime.minimumSwiftCodeVersion)\" is not valid semver.",
                suggestion: "Use a semver string such as \"1.0.0\".",
                line: findLine(ofKey: "minimumSwiftCodeVersion", in: rawText)
            ))
        }

        // SDK ref checks
        if manifest.sdk.name != requiredSDKName {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "sdk.name",
                message: "SDK name must be \"\(requiredSDKName)\", got \"\(manifest.sdk.name)\".",
                suggestion: "Set \"sdk.name\" to \"\(requiredSDKName)\".",
                line: findLine(ofKey: "sdk", in: rawText)
            ))
        }
        if !isSDKRangeCompatible(manifest.sdk.versionRange) {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "sdk.versionRange",
                message: "SDK versionRange \"\(manifest.sdk.versionRange)\" is incompatible with host SDK 1.2.0.",
                suggestion: "Use \"1.2.0\", \"^1.0.0\", \"^1.1.0\", or \"^1.2.0\".",
                line: findLine(ofKey: "versionRange", in: rawText)
            ))
        }
        if manifest.sdk.protocolVersion != supportedProtocolVersion {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .error,
                field: "sdk.protocolVersion",
                message: "Unsupported protocolVersion \(manifest.sdk.protocolVersion) (expected 1).",
                suggestion: "Set \"sdk.protocolVersion\" to 1.",
                line: findLine(ofKey: "protocolVersion", in: rawText)
            ))
        }

        // Capability checks
        var seenCaps = Set<String>()
        let validCaps = supportedCapabilities
        for (idx, cap) in manifest.capabilities.enumerated() {
            let fieldPath = "capabilities[\(idx)]"
            let line = findLine(ofValue: cap.id, in: rawText) ?? findLine(ofKey: "capabilities", in: rawText)
            if !validCaps.contains(cap.id) {
                diagnostics.append(SDKManifestDiagnostic(
                    severity: .error,
                    field: "\(fieldPath).id",
                    message: "Unknown capability ID \"\(cap.id)\".",
                    suggestion: "Select a valid capability from the SwiftCode SDK Capability Registry.",
                    line: line
                ))
            }
            if !seenCaps.insert(cap.id).inserted {
                diagnostics.append(SDKManifestDiagnostic(
                    severity: .error,
                    field: "\(fieldPath).id",
                    message: "Duplicate capability ID \"\(cap.id)\".",
                    suggestion: "Remove the duplicate entry for \"\(cap.id)\".",
                    line: line
                ))
            }
            let reason = cap.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if reason.isEmpty {
                diagnostics.append(SDKManifestDiagnostic(
                    severity: .error,
                    field: "\(fieldPath).reason",
                    message: "Capability \"\(cap.id)\" is missing a required reason.",
                    suggestion: "Provide a user-facing explanation of why this capability is needed.",
                    line: line
                ))
            } else if reason.count > maxReasonLength {
                diagnostics.append(SDKManifestDiagnostic(
                    severity: .error,
                    field: "\(fieldPath).reason",
                    message: "Capability \"\(cap.id)\" reason exceeds 512 characters.",
                    suggestion: "Shorten the capability justification to 512 characters or fewer.",
                    line: line
                ))
            }

            if let granted = grantedCapabilities, validCaps.contains(cap.id), !granted.contains(cap.id) {
                diagnostics.append(SDKManifestDiagnostic(
                    severity: .warning,
                    field: "\(fieldPath).id",
                    message: "Capability \"\(cap.id)\" is declared in manifest but not yet granted in the active API Key / Grant Store.",
                    suggestion: "Grant \"\(cap.id)\" in Studio → Permissions or API Keys before invoking it at runtime.",
                    line: line
                ))
            }
        }

        if manifest.assist.requested && !seenCaps.contains("assist.invoke") {
            diagnostics.append(SDKManifestDiagnostic(
                severity: .warning,
                field: "assist.requested",
                message: "\"assist.requested\" is true, but \"assist.invoke\" is not listed in capabilities.",
                suggestion: "Add the \"assist.invoke\" capability if this extension invokes Assist.",
                line: findLine(ofKey: "assist", in: rawText)
            ))
        }

        // Command checks
        if let cmds = manifest.contributes?.commands {
            var seenCmds = Set<String>()
            for (idx, cmd) in cmds.enumerated() {
                let fieldPath = "contributes.commands[\(idx)]"
                let line = findLine(ofValue: cmd.id, in: rawText) ?? findLine(ofKey: "commands", in: rawText)
                if !matches(cmd.id, pattern: #"^[a-z][a-z0-9.-]{0,63}$"#) {
                    diagnostics.append(SDKManifestDiagnostic(
                        severity: .error,
                        field: "\(fieldPath).id",
                        message: "Command ID \"\(cmd.id)\" is invalid.",
                        suggestion: "Use lowercase kebab-case starting with a letter, e.g. \"run-build\".",
                        line: line
                    ))
                }
                if !seenCmds.insert(cmd.id).inserted {
                    diagnostics.append(SDKManifestDiagnostic(
                        severity: .error,
                        field: "\(fieldPath).id",
                        message: "Duplicate command ID \"\(cmd.id)\".",
                        suggestion: "Give every contributed command a unique ID.",
                        line: line
                    ))
                }
                if cmd.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    diagnostics.append(SDKManifestDiagnostic(
                        severity: .error,
                        field: "\(fieldPath).title",
                        message: "Command \"\(cmd.id)\" has a blank title.",
                        suggestion: "Provide a human-readable title for the command.",
                        line: line
                    ))
                }
            }
        }

        if !manifest.unknownFields.isEmpty {
            let keys = manifest.unknownFields.keys.sorted().joined(separator: ", ")
            diagnostics.append(SDKManifestDiagnostic(
                severity: .info,
                field: "unknownFields",
                message: "Preserving custom top-level field(s): \(keys).",
                suggestion: "Custom fields are preserved across visual edits.",
                line: 1
            ))
        }

        return diagnostics
    }

    // MARK: - Identity

    private static func validateIdentity(_ manifest: SDKManifest) throws {
        let id = manifest.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw invalid("The extension \"id\" must not be blank.",
                          suggestion: "Set \"id\" to a reverse-DNS identifier, e.g. \"com.example.my-extension\".")
        }
        guard id.count <= maxIDLength else {
            throw invalid("The extension \"id\" exceeds 128 characters.",
                          suggestion: "Shorten the extension ID to 128 characters or fewer.")
        }
        guard matches(id, pattern: #"^[a-z0-9]+(\.[a-z0-9-]+)+$"#) else {
            throw invalid("The extension ID \"\(id)\" is not a valid reverse-DNS identifier.",
                          suggestion: "Use lowercase letters, digits, and hyphens separated by dots, e.g. \"com.example.my-extension\".")
        }

        let name = manifest.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw invalid("The extension \"name\" must not be blank.",
                          suggestion: "Give the extension a human-readable \"name\".")
        }
        guard name.count <= maxNameLength else {
            throw invalid("The extension \"name\" exceeds 128 characters.",
                          suggestion: "Shorten the extension name to 128 characters or fewer.")
        }

        let version = manifest.version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw invalid("The extension \"version\" must not be blank.",
                          suggestion: "Set \"version\" to a semver string such as \"0.1.0\".")
        }
        guard version.count <= maxVersionLength else {
            throw invalid("The extension \"version\" exceeds 32 characters.",
                          suggestion: "Shorten the version string to 32 characters or fewer.")
        }
        guard matches(version, pattern: #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#) else {
            throw invalid("The extension \"version\" \"\(version)\" is not valid semver.",
                          suggestion: "Use a semver version such as \"0.1.0\" or \"1.2.3-beta.1\".")
        }

        if let description = manifest.description, description.count > maxDescriptionLength {
            throw invalid("The extension \"description\" exceeds 1024 characters.",
                          suggestion: "Shorten the description to 1024 characters or fewer.")
        }

        let type = manifest.type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty else {
            throw invalid("The extension \"type\" must not be blank.",
                          suggestion: "Set \"type\" to \"extension\".")
        }
        guard type.count <= maxNameLength else {
            throw invalid("The extension \"type\" exceeds 128 characters.",
                          suggestion: "Set \"type\" to \"extension\".")
        }
    }

    // MARK: - Runtime

    private static func validateRuntime(_ runtime: SDKManifestRuntime) throws {
        guard runtime.language == "typescript" else {
            throw invalid("Unsupported runtime language \"\(runtime.language)\".",
                          suggestion: "The v1 runtime supports TypeScript extensions only — set \"runtime.language\" to \"typescript\".")
        }

        let entrypoint = runtime.entrypoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entrypoint.isEmpty else {
            throw invalid("The runtime \"entrypoint\" must not be blank.",
                          suggestion: "Set \"runtime.entrypoint\" to the extension's built JS file, e.g. \"dist/index.js\".")
        }
        guard entrypoint.count <= maxEntrypointLength else {
            throw invalid("The runtime \"entrypoint\" exceeds 512 characters.",
                          suggestion: "Use a shorter relative path for the entrypoint.")
        }
        // Lexical traversal checks only (no I/O here — the package validator
        // re-checks with real symlink resolution).
        guard !entrypoint.hasPrefix("/") else {
            throw SDKError(
                code: .pathTraversal,
                message: "The runtime entrypoint must be a relative path inside the package.",
                suggestion: "Use a relative path such as \"dist/index.js\" instead of an absolute path."
            )
        }
        let segments = entrypoint.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !segments.contains("..") else {
            throw SDKError(
                code: .pathTraversal,
                message: "The runtime entrypoint must not contain \"..\" segments.",
                suggestion: "Point \"runtime.entrypoint\" at a file inside the package, e.g. \"dist/index.js\"."
            )
        }
        guard segments.allSatisfy({ !$0.isEmpty }) else {
            throw invalid("The runtime \"entrypoint\" contains empty path segments.",
                          suggestion: "Use a clean relative path such as \"dist/index.js\".")
        }

        let minimum = runtime.minimumSwiftCodeVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !minimum.isEmpty else {
            throw invalid("The runtime \"minimumSwiftCodeVersion\" must not be blank.",
                          suggestion: "Set \"runtime.minimumSwiftCodeVersion\" to a semver string such as \"1.0.0\".")
        }
        guard minimum.count <= maxVersionLength else {
            throw invalid("The runtime \"minimumSwiftCodeVersion\" exceeds 32 characters.",
                          suggestion: "Use a semver version such as \"1.0.0\".")
        }
        guard matches(minimum, pattern: #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#) else {
            throw invalid("The runtime \"minimumSwiftCodeVersion\" \"\(minimum)\" is not valid semver.",
                          suggestion: "Use a semver version such as \"1.0.0\".")
        }
    }

    // MARK: - SDK reference

    private static func validateSDKRef(_ sdk: SDKManifestSDKRef) throws {
        guard sdk.name == requiredSDKName else {
            throw SDKError(
                code: .incompatibleSDKVersion,
                message: "The manifest references SDK \"\(sdk.name)\" instead of \"\(requiredSDKName)\".",
                suggestion: "Set \"sdk.name\" to \"\(requiredSDKName)\"."
            )
        }
        guard isSDKRangeCompatible(sdk.versionRange) else {
            throw SDKError(
                code: .incompatibleSDKVersion,
                message: "The SDK version range \"\(sdk.versionRange)\" is not supported by this SwiftCode release (SDK 1.2.0).",
                suggestion: "Use one of: \"1.0.0\", \"1.1.0\", \"1.2.0\", \"^1.0.0\", \"^1.1.0\", \"^1.2.0\", \"~1.2.0\", or \">=1.0.0 <2.0.0\"."
            )
        }
        guard sdk.protocolVersion == supportedProtocolVersion else {
            throw SDKError(
                code: .incompatibleSDKVersion,
                message: "Unsupported protocol version \(sdk.protocolVersion). This SwiftCode release supports protocol version 1.",
                suggestion: "Set \"sdk.protocolVersion\" to 1, or update SwiftCode to a release that supports this protocol."
            )
        }
    }

    // MARK: - Capabilities

    private static func validateCapabilities(_ capabilities: [SDKManifestCapability]) throws {
        guard capabilities.count <= maxCapabilities else {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "The manifest requests \(capabilities.count) capabilities; the limit is \(maxCapabilities).",
                suggestion: "Request at most \(maxCapabilities) capabilities."
            )
        }
        let validCapabilities = supportedCapabilities
        var seenIDs = Set<String>()
        for capability in capabilities {
            guard validCapabilities.contains(capability.id) else {
                throw SDKError(
                    code: .unknownCapability,
                    message: "Unknown capability \"\(capability.id)\".",
                    suggestion: "Use only capability IDs from the published registry (e.g. \"source-control.read\", \"build.execute\").",
                    diagnostics: ["capabilityId": capability.id]
                )
            }
            guard seenIDs.insert(capability.id).inserted else {
                throw invalid("Duplicate capability ID \"\(capability.id)\".",
                              suggestion: "List each requested capability at most once in swiftcode.json.")
            }
            let reason = capability.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reason.isEmpty else {
                throw invalid("Capability \"\(capability.id)\" is missing its justification.",
                              suggestion: "Add a \"reason\" explaining why the extension needs this capability.")
            }
            guard reason.count <= maxReasonLength else {
                throw invalid("Capability \"\(capability.id)\" has a reason longer than 512 characters.",
                              suggestion: "Shorten the capability reason to 512 characters or fewer.")
            }
        }
    }

    // MARK: - Contributions

    private static func validateContributions(_ contributions: SDKManifestContributions?) throws {
        guard let contributions else { return }
        guard contributions.commands.count <= maxCommands else {
            throw SDKError(
                code: .resourceLimitExceeded,
                message: "The manifest contributes \(contributions.commands.count) commands; the limit is \(maxCommands).",
                suggestion: "Contribute at most \(maxCommands) commands."
            )
        }
        var seenIDs = Set<String>()
        for command in contributions.commands {
            guard matches(command.id, pattern: #"^[a-z][a-z0-9.-]{0,63}$"#) else {
                throw invalid("Command ID \"\(command.id)\" is invalid.",
                              suggestion: "Use a lowercase kebab-case ID starting with a letter, up to 64 characters, e.g. \"run-build\".")
            }
            guard seenIDs.insert(command.id).inserted else {
                throw invalid("Duplicate command ID \"\(command.id)\".",
                              suggestion: "Give every contributed command a unique ID.")
            }
            let title = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                throw invalid("Command \"\(command.id)\" has a blank title.",
                              suggestion: "Provide a human-readable \"title\" for the command.")
            }
            guard title.count <= maxCommandTitleLength else {
                throw invalid("Command \"\(command.id)\" has a title longer than 128 characters.",
                              suggestion: "Shorten the command title to 128 characters or fewer.")
            }
        }
    }

    // MARK: - Semver range compatibility

    /// A range is compatible when it admits the host SDK 1.x release line (1.0.0 .. 1.2.0).
    /// Supported forms: exact `1.0.0` / `1.1.0` / `1.2.0`, `^1.0.0` / `^1.1.0` / `^1.2.0`,
    /// `~1.0.0` / `~1.1.0` / `~1.2.0`, or `>=1.x.0 <2.0.0`.
    public static func isSDKRangeCompatible(_ range: String) -> Bool {
        let trimmed = range.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (major: hostSDKVersion.major, minor: hostSDKVersion.minor, patch: hostSDKVersion.patch)

        if trimmed.hasPrefix("^") || trimmed.hasPrefix("~") {
            let core = String(trimmed.dropFirst())
            guard let version = parseSemverCore(core), version.prerelease == nil else { return false }
            return version.major == host.major && compareSemver(version, host) <= 0
        }

        if let exact = parseSemverCore(trimmed) {
            return exact.prerelease == nil
                && exact.major == host.major
                && compareSemver(exact, host) <= 0
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 2,
              parts[0].hasPrefix(">="),
              parts[1].hasPrefix("<"),
              let lower = parseSemverCore(String(parts[0].dropFirst(2))),
              let upper = parseSemverCore(String(parts[1].dropFirst(1))),
              lower.prerelease == nil, upper.prerelease == nil else { return false }
        return compareSemver(lower, host) <= 0 && compareSemver(upper, host) > 0
    }

    private struct SemverCore {
        let major: Int
        let minor: Int
        let patch: Int
        let prerelease: String?
    }

    private static func parseSemverCore(_ value: String) -> SemverCore? {
        let coreAndPrerelease = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard coreAndPrerelease.count <= 2 else { return nil }
        let numbers = coreAndPrerelease[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              let major = Int(numbers[0]), let minor = Int(numbers[1]), let patch = Int(numbers[2]),
              numbers.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let prerelease = coreAndPrerelease.count == 2 ? String(coreAndPrerelease[1]) : nil
        if let prerelease, prerelease.isEmpty { return nil }
        return SemverCore(major: major, minor: minor, patch: patch, prerelease: prerelease)
    }

    private static func compareSemver(_ lhs: SemverCore, _ rhs: (major: Int, minor: Int, patch: Int)) -> Int {
        if lhs.major != rhs.major { return lhs.major < rhs.major ? -1 : 1 }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor ? -1 : 1 }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch ? -1 : 1 }
        return 0
    }

    // MARK: - Line Lookup Helpers

    private static func findLine(ofKey key: String, in rawText: String) -> Int? {
        let needle = "\"\(key)\""
        let lines = rawText.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() where line.contains(needle) {
            return idx + 1
        }
        return nil
    }

    private static func findLine(ofValue value: String, in rawText: String) -> Int? {
        guard !value.isEmpty else { return nil }
        let needle = "\"\(value)\""
        let lines = rawText.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() where line.contains(needle) {
            return idx + 1
        }
        return nil
    }

    private static func extractJSONErrorLine(from error: Error, in rawText: String) -> Int? {
        let nsError = error as NSError
        if let debugDesc = nsError.userInfo["NSDebugDescription"] as? String {
            if let range = debugDesc.range(of: #"line (\d+)"#, options: .regularExpression) {
                let digits = debugDesc[range].filter(\.isNumber)
                if let line = Int(digits) { return line }
            }
        }
        return 1
    }

    // MARK: - Helpers

    private static func invalid(_ message: String, suggestion: String) -> SDKError {
        SDKError(code: .manifestInvalid, message: message, suggestion: suggestion)
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return expression.firstMatch(in: value, range: range) != nil
    }
}
