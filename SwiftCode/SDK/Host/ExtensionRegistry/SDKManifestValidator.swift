import Foundation

// MARK: - SDKManifestValidator
//
// Strict, PURE manifest validation for `swiftcode.json` (spec §7.2, §7.3).
// Performs no I/O: it validates the manifest bytes only. Package-level checks
// (entrypoint existence, symlink containment, executables) live in
// `SDKPackageValidator`.
//
// Every rejection is an `SDKError` with a user-safe message and an actionable
// suggestion. Thread-safe: value types and static functions only, no shared
// mutable state.

public enum SDKManifestValidator {

    // MARK: - Limits

    /// Manifests larger than this are rejected before parsing.
    private static let maxManifestBytes = 64 * 1024
    private static let supportedManifestVersion = 1
    private static let supportedProtocolVersion = 1
    private static let requiredSDKName = "@swiftcode/sdk"
    /// Host SDK version this validator checks compatibility against
    /// (additive release 1.2.0: use.Security family, deployConsole.view,
    /// virtualization.view, sandbox.view re-targeting, new security.*
    /// IPC routes).
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

    /// The fixed v1 capability registry (ADR §7). Unknown IDs are rejected —
    /// never silently reinterpreted as a known capability (spec §7.3).
    private static let supportedCapabilities: Set<String> = [
        "project.read",
        "workspace.read",
        "workspace.write",
        "source-control.read",
        "source-control.write",
        "build.execute",
        "task.execute",
        "network.request",
        "ui.contribute",
        "credentials.use",
        "assist.invoke",
    ]

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
                suggestion: "Use one of: \"1.2.0\", \"^1.2.0\", \"~1.2.0\", or \">=1.2.0 <2.0.0\"."
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
        for capability in capabilities {
            guard supportedCapabilities.contains(capability.id) else {
                throw SDKError(
                    code: .unknownCapability,
                    message: "Unknown capability \"\(capability.id)\".",
                    suggestion: "Use only capability IDs from the published v1 registry (e.g. \"source-control.read\", \"build.execute\").",
                    diagnostics: ["capabilityId": capability.id]
                )
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
            guard matches(command.id, pattern: #"^[a-z][a-z0-9-]{0,63}$"#) else {
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

    /// A range is compatible when it admits the host SDK version (1.2.0).
    /// Supported forms only: exact `1.2.0`, `^1.2.0`, `~1.2.0`,
    /// `>=1.2.0 <2.0.0`. Anything else is rejected.
    private static func isSDKRangeCompatible(_ range: String) -> Bool {
        let trimmed = range.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = (major: hostSDKVersion.major, minor: hostSDKVersion.minor, patch: hostSDKVersion.patch)

        if trimmed.hasPrefix("^") || trimmed.hasPrefix("~") {
            let core = String(trimmed.dropFirst())
            guard let version = parseSemverCore(core), version.prerelease == nil else { return false }
            return version.major == host.major && version.minor == host.minor && version.patch == host.patch
        }

        if let exact = parseSemverCore(trimmed) {
            return exact.prerelease == nil
                && exact.major == host.major
                && exact.minor == host.minor
                && exact.patch == host.patch
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 2,
              parts[0].hasPrefix(">="),
              parts[1].hasPrefix("<"),
              let lower = parseSemverCore(String(parts[0].dropFirst(2))),
              let upper = parseSemverCore(String(parts[1].dropFirst(1))),
              lower.prerelease == nil, upper.prerelease == nil else { return false }
        return compareSemver(lower, host) <= 0 && compareSemver(host, upper) < 0
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
