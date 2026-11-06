import Foundation

// MARK: - Semantic versions and engine requirements

/// Minimal semver value object. Pre-release/build suffixes are stripped for
/// comparison (they never make an engine requirement pass that a release
/// would fail); the original string is kept for display.
public struct ExtV2Version: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let original: String

    public var description: String { original }

    public init?(string: String) {
        let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^v", with: "", options: .regularExpression)
        let core = cleaned.split(separator: "-", maxSplits: 1).first.map(String.init) ?? cleaned
        let parts = core.split(separator: ".").map(String.init)
        guard let major = parts.first.flatMap(Int.init) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        self.patch = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
        self.original = cleaned
    }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major; self.minor = minor; self.patch = patch
        self.original = "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: ExtV2Version, rhs: ExtV2Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Evaluates the requirement forms VS Code extensions actually use:
    /// `*`, `x`, `^1.80.0`, `>=1.80.0`, `1.80.0`, and `1.80.x`.
    /// Anything unparseable is a failure, never a silent pass.
    public func satisfies(engineRequirement requirement: String) -> Bool {
        let req = requirement.trimmingCharacters(in: .whitespacesAndNewlines)
        if req == "*" || req == "x" || req.isEmpty { return true }
        if req.hasPrefix(">=") {
            guard let floor = ExtV2Version(string: String(req.dropFirst(2))) else { return false }
            return self >= floor
        }
        if req.hasPrefix("^") {
            guard let base = ExtV2Version(string: String(req.dropFirst())) else { return false }
            // Caret: same major, at least the base version.
            return major == base.major && self >= base
        }
        if req.hasSuffix(".x") || req.hasSuffix(".*") {
            let prefix = req.replacingOccurrences(of: ".x", with: "")
                .replacingOccurrences(of: ".*", with: "")
            let parts = prefix.split(separator: ".").map(String.init)
            guard let pMajor = parts.first.flatMap(Int.init) else { return false }
            if parts.count == 1 { return major == pMajor }
            guard parts.count >= 2, let pMinor = Int(parts[1]) else { return false }
            return major == pMajor && minor == pMinor
        }
        guard let exact = ExtV2Version(string: req) else { return false }
        return self == exact
    }
}

// MARK: - API compatibility matrix

public enum ExtV2APILevel: String, Codable, Sendable {
    case supported
    case partial
    case unsupported

    public var displayName: String {
        switch self {
        case .supported: return "Supported"
        case .partial: return "Partial"
        case .unsupported: return "Unsupported"
        }
    }
}

/// The versioned API matrix. This is the contract the UI and diagnostics
/// render; adding an API means adding a row here *and* an implementation,
/// never a success-returning stub.
public enum ExtV2VSCodeAPI {
    /// The VS Code engine version SwiftCode's host claims compatibility with.
    /// Extensions requiring newer engines are reported incompatible, not
    /// loaded and hoped for.
    public static let hostEngineVersion = ExtV2Version(major: 1, minor: 85, patch: 0)

    public static let matrix: [String: ExtV2APILevel] = [
        "commands": .supported,
        "window.showInformationMessage": .supported,
        "window.showWarningMessage": .supported,
        "window.showErrorMessage": .supported,
        "window.createOutputChannel": .supported,
        "window.showQuickPick": .supported,
        "window.showInputBox": .supported,
        "window.withProgress": .partial,
        "workspace.fs": .supported,
        "workspace.openTextDocument": .supported,
        "workspace.applyEdit": .supported,
        "workspace.getConfiguration": .supported,
        "workspace.onDidChangeTextDocument": .supported,
        "languages.registerCompletionItemProvider": .supported,
        "languages.registerHoverProvider": .supported,
        "languages.registerDefinitionProvider": .supported,
        "languages.registerReferenceProvider": .supported,
        "languages.registerRenameProvider": .supported,
        "languages.registerDocumentFormattingEditProvider": .supported,
        "languages.registerCodeActionProvider": .supported,
        "languages.createDiagnosticCollection": .supported,
        "extensions.getExtension": .supported,
        "StatusBarItem": .supported,
        "TreeDataProvider": .supported,
        "WebviewViewProvider": .partial,
        "tasks": .partial,
        "terminal": .partial,
        "debug": .unsupported,
        "notebooks": .unsupported,
        "testing": .unsupported,
        "authentication": .unsupported,
        "secrets": .unsupported,
        "CustomEditor": .unsupported,
        "FileSystemProvider": .unsupported,
        "SourceControl": .partial,
        "themes": .partial,
        "snippets": .supported,
        "grammars": .partial,
    ]

    public static func level(for api: String) -> ExtV2APILevel {
        matrix[api] ?? .unsupported
    }
}

public struct ExtV2CompatibilityReport: Sendable {
    public let compatible: Bool
    public let reasons: [String]
    public let engineRequirement: String?
    public let unsupportedAPIs: [String]

    public init(compatible: Bool, reasons: [String], engineRequirement: String?, unsupportedAPIs: [String]) {
        self.compatible = compatible
        self.reasons = reasons
        self.engineRequirement = engineRequirement
        self.unsupportedAPIs = unsupportedAPIs
    }
}

/// Pure compatibility evaluation, unit-testable without any process or UI.
public enum ExtV2Compatibility {
    public static func evaluate(manifest: ExtV2VSCodeManifest) -> ExtV2CompatibilityReport {
        var reasons: [String] = []
        var unsupported: [String] = []

        if let engine = manifest.enginesVscode {
            if !ExtV2VSCodeAPI.hostEngineVersion.satisfies(engineRequirement: engine) {
                reasons.append("Requires VS Code engine \(engine); SwiftCode's host supports \(ExtV2VSCodeAPI.hostEngineVersion.original).")
            }
        } else {
            reasons.append("Manifest declares no engines.vscode requirement, so compatibility cannot be verified.")
        }
        if manifest.main == nil && manifest.browser == nil {
            // Language-only contributions (grammars, snippets, themes) are
            // still usable without an activation entry point.
            let languageOnly = !(manifest.contributesCommands.isEmpty
                && manifest.contributesViews.isEmpty)
            if languageOnly {
                reasons.append("No main entry point; only declarative contributions can run.")
            }
        }
        for api in manifest.declaredAPIs {
            if ExtV2VSCodeAPI.level(for: api) == .unsupported {
                unsupported.append(api)
            }
        }
        if !unsupported.isEmpty {
            reasons.append("Uses unsupported APIs: \(unsupported.joined(separator: ", ")).")
        }
        return ExtV2CompatibilityReport(
            compatible: reasons.isEmpty,
            reasons: reasons,
            engineRequirement: manifest.enginesVscode,
            unsupportedAPIs: unsupported
        )
    }
}
