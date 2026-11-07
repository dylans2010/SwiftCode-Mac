import Foundation

public struct SDKVersions: Codable, Sendable {
    public let hostSDKVersion: String
    public let hostProtocolVersion: Int
    public let hostApiVersion: String

    public init(hostSDKVersion: String, hostProtocolVersion: Int, hostApiVersion: String) {
        self.hostSDKVersion = hostSDKVersion
        self.hostProtocolVersion = hostProtocolVersion
        self.hostApiVersion = hostApiVersion
    }
}

public enum SDKCompatibility {
    public static let currentProtocolVersion: Int = 1

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

    func isSatisfied(by host: SemanticVersion) -> Bool {
        switch op {
        case .exact:
            return host == version
        case .atLeast:
            return host >= version
        case .caret:
            guard host >= version else { return false }
            if version.major > 0 { return host.major == version.major }
            if version.minor > 0 { return host.major == 0 && host.minor == version.minor }
            return host == version
        case .tilde:
            guard host >= version else { return false }
            return host.major == version.major && host.minor == version.minor
        }
    }

    struct SemanticVersion: Comparable, Sendable {
        let major: Int
        let minor: Int
        let patch: Int

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
