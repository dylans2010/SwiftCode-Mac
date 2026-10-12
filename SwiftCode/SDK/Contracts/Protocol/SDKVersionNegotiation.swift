import Foundation

// MARK: - SDKVersions
//
// The host's version facts, sourced from the canonical
// `SwiftCodeSDK.json` (spec §18.1). These are the "host" side of the
// compatibility check: the extension's manifest declares what it needs,
// the host declares what it is, and `SDKCompatibility.check` reconciles
// them. The version concepts are deliberately NOT interchangeable
// (spec §18): SDK package version, protocol version, and API version are
// checked independently.

public struct SDKVersions: Codable, Sendable {
    /// Host SDK package version, e.g. `"1.0.0"`.
    public let hostSDKVersion: String
    /// Host/runtime IPC protocol version (currently 1).
    public let hostProtocolVersion: Int
    /// Host internal API version, e.g. `"2026.1"`. Informational: surfaced
    /// for diagnostics, not used in the compatibility decision.
    public let hostApiVersion: String

    public init(hostSDKVersion: String, hostProtocolVersion: Int, hostApiVersion: String) {
        self.hostSDKVersion = hostSDKVersion
        self.hostProtocolVersion = hostProtocolVersion
        self.hostApiVersion = hostApiVersion
    }
}

// MARK: - SDKCompatibility
//
// Pure version-negotiation logic (spec §18.2): no I/O, no singletons.
// Throws typed `SDKError`s so failures flow through the standard
// error taxonomy (`.ipcProtocolMismatch`, `.incompatibleSDKVersion`).

public enum SDKCompatibility {
    /// The protocol version this host speaks (spec §18, ADR §10).
    public static let currentProtocolVersion: Int = 1

    /// Validates an extension's declared requirements against the host.
    /// - Parameters:
    ///   - manifestProtocolVersion: the `protocolVersion` the extension's
    ///     manifest was written against. Must equal
    ///     `currentProtocolVersion` exactly — protocol versions are never
    ///     range-negotiated.
    ///   - sdkVersionRange: the SDK version range the extension requires,
    ///     using the same range semantics as the manifest validator:
    ///     `^` (compatible), `~` (patch-compatible), `>=` (minimum), or an
    ///     exact version (e.g. `"1.0.0"`). The host's SDK version must
    ///     satisfy the range.
    ///   - host: the host's version facts.
    /// - Throws: `SDKError` with `.ipcProtocolMismatch` when the protocol
    ///   versions differ, `.manifestInvalid` when the range is malformed,
    ///   `.serviceUnavailable` when the host's own version metadata is
    ///   malformed, or `.incompatibleSDKVersion` when the host SDK does not
    ///   satisfy the required range.
    public static func check(
        manifestProtocolVersion: Int,
        sdkVersionRange: String,
        host: SDKVersions
    ) throws {
        guard manifestProtocolVersion == currentProtocolVersion else {
            throw SDKError(
                code: .ipcProtocolMismatch,
                message: "Extension requires IPC protocol version \(manifestProtocolVersion); this host speaks version \(currentProtocolVersion).",
                suggestion: "Update the extension or SwiftCode so both use protocol version \(currentProtocolVersion)."
            )
        }
        guard let range = SDKVersionRange(sdkVersionRange) else {
            throw SDKError(
                code: .manifestInvalid,
                message: "The extension's SDK version requirement \"\(sdkVersionRange)\" is not a valid range.",
                suggestion: "Use ^, ~, >=, or an exact version (e.g. \"^1.0.0\")."
            )
        }
        guard let hostVersion = SDKVersionRange.SemanticVersion(host.hostSDKVersion) else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The host's SDK version metadata is invalid.",
                suggestion: "Reinstall or update SwiftCode.",
                diagnostics: ["hostSDKVersion": host.hostSDKVersion]
            )
        }
        guard range.isSatisfied(by: hostVersion) else {
            throw SDKError(
                code: .incompatibleSDKVersion,
                message: "Extension requires SDK \(sdkVersionRange); this host provides SDK \(host.hostSDKVersion).",
                suggestion: "Install an extension build compatible with SwiftCode SDK \(host.hostSDKVersion), or update SwiftCode."
            )
        }
    }
}

// MARK: - SDKVersionRange
//
// npm-style version range semantics shared with the manifest validator:
// `^1.2.3` compatible release, `~1.2.3` patch-compatible, `>=1.2.3`
// minimum, or an exact version. Internal to the negotiation logic.

struct SDKVersionRange {
    enum Operator {
        case exact, caret, tilde, atLeast
    }

    let op: Operator
    let version: SemanticVersion

    init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(">=") {
            guard let v = SemanticVersion(String(trimmed.dropFirst(2))) else { return nil }
            self.op = .atLeast
            self.version = v
        } else if trimmed.hasPrefix("^") {
            guard let v = SemanticVersion(String(trimmed.dropFirst(1))) else { return nil }
            self.op = .caret
            self.version = v
        } else if trimmed.hasPrefix("~") {
            guard let v = SemanticVersion(String(trimmed.dropFirst(1))) else { return nil }
            self.op = .tilde
            self.version = v
        } else {
            guard let v = SemanticVersion(trimmed) else { return nil }
            self.op = .exact
            self.version = v
        }
    }

    /// Whether `host` satisfies this range.
    func isSatisfied(by host: SemanticVersion) -> Bool {
        switch op {
        case .exact:
            return host == version
        case .atLeast:
            return host >= version
        case .caret:
            // ^1.2.3 := >=1.2.3 <2.0.0; ^0.2.3 := >=0.2.3 <0.3.0;
            // ^0.0.3 := 0.0.3 exactly.
            guard host >= version else { return false }
            if version.major > 0 { return host.major == version.major }
            if version.minor > 0 { return host.major == 0 && host.minor == version.minor }
            return host == version
        case .tilde:
            // ~1.2.3 := >=1.2.3 <1.3.0
            guard host >= version else { return false }
            return host.major == version.major && host.minor == version.minor
        }
    }

    struct SemanticVersion: Comparable, Sendable {
        let major: Int
        let minor: Int
        let patch: Int

        /// Parses `major[.minor[.patch]]`; prerelease (`-…`) and build
        /// (`+…`) suffixes are ignored for comparison. Returns nil for
        /// non-numeric or empty components.
        init?(_ raw: String) {
            var core = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let dash = core.firstIndex(of: "-") { core = String(core[..<dash]) }
            if let plus = core.firstIndex(of: "+") { core = String(core[..<plus]) }
            let parts = core.split(separator: ".", omittingEmptySubsequences: false)
            guard (1...3).contains(parts.count) else { return nil }
            var numbers: [Int] = []
            for part in parts {
                guard !part.isEmpty, part.allSatisfy(\.isNumber), let n = Int(part) else { return nil }
                numbers.append(n)
            }
            self.major = numbers[0]
            self.minor = numbers.count > 1 ? numbers[1] : 0
            self.patch = numbers.count > 2 ? numbers[2] : 0
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }

        static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch
        }
    }
}
