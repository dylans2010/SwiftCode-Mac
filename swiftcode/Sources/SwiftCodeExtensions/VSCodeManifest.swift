import Foundation

public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let original: String

    public var description: String { original }

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.original = "\(major).\(minor).\(patch)"
    }

    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        var core = trimmed
        if core.hasPrefix("v") { core.removeFirst() }
        if let dash = core.firstIndex(of: "-") { core = String(core[core.startIndex..<dash]) }
        guard !core.isEmpty else { return nil }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard let major = Int(parts[0]) else { return nil }
        let minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        let patch = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
        self.major = major
        self.minor = minor
        self.patch = patch
        self.original = trimmed
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public func satisfies(engineRequirement requirement: String) -> Bool {
        let req = requirement.trimmingCharacters(in: .whitespaces)
        if req.isEmpty || req == "*" || req.lowercased() == "x" { return true }
        if req.hasPrefix(">=") {
            guard let floor = SemanticVersion(string: String(req.dropFirst(2))) else { return false }
            return self >= floor
        }
        if req.hasPrefix("^") {
            guard let base = SemanticVersion(string: String(req.dropFirst())) else { return false }
            return major == base.major && self >= base
        }
        if req.hasSuffix(".x") || req.hasSuffix(".*") {
            let core = String(req.dropLast(2))
            let parts = core.split(separator: ".")
            guard let reqMajor = Int(parts[0]) else { return false }
            guard reqMajor == major else { return false }
            if parts.count > 1 {
                guard let reqMinor = Int(parts[1]) else { return false }
                return reqMinor == minor
            }
            return true
        }
        guard let exact = SemanticVersion(string: req) else { return false }
        return self == exact
    }
}

public enum ExtensionAPILevel: String, Codable, Sendable {
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

public enum VSCodeAPI {
    public static let hostEngineVersion = SemanticVersion(major: 1, minor: 85, patch: 0)

    public static let matrix: [String: ExtensionAPILevel] = [
        "commands": .supported,
        "window.showInformationMessage": .supported,
        "window.showWarningMessage": .supported,
        "window.showErrorMessage": .supported,
        "window.createOutputChannel": .supported,
        "window.showQuickPick": .supported,
        "window.showInputBox": .supported,
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
        "snippets": .supported,
        "window.withProgress": .partial,
        "WebviewViewProvider": .partial,
        "tasks": .partial,
        "terminal": .partial,
        "SourceControl": .partial,
        "themes": .partial,
        "grammars": .partial,
        "debug": .unsupported,
        "notebooks": .unsupported,
        "testing": .unsupported,
        "authentication": .unsupported,
        "secrets": .unsupported,
        "CustomEditor": .unsupported,
        "FileSystemProvider": .unsupported,
    ]

    public static func level(for api: String) -> ExtensionAPILevel {
        matrix[api] ?? .unsupported
    }

    public static let unsupportedAPIs: [String] = [
        "vscode.debug",
        "vscode.notebooks",
        "vscode.tests",
        "vscode.authentication",
        "vscode.SecretStorage",
        "vscode.CustomEditor",
        "vscode.FileSystemProvider",
        "vscode.Terminal.createTerminal (full PTY)",
    ]
}

public struct CompatibilityReport: Sendable {
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

public enum Compatibility {
    public static func evaluate(manifest: VSCodeManifest) -> CompatibilityReport {
        var reasons: [String] = []
        var unsupported: [String] = []
        if let requirement = manifest.enginesVscode {
            if !VSCodeAPI.hostEngineVersion.satisfies(engineRequirement: requirement) {
                reasons.append("Requires VS Code engine \(requirement); SwiftCode's host supports 1.85.0.")
            }
        } else {
            reasons.append("Manifest declares no engines.vscode requirement, so compatibility cannot be verified.")
        }
        if manifest.main == nil && manifest.browser == nil
            && (!manifest.contributesCommands.isEmpty || !manifest.contributesViews.isEmpty) {
            reasons.append("No main entry point; only declarative contributions can run.")
        }
        for api in manifest.declaredAPIs where VSCodeAPI.level(for: api) == .unsupported {
            unsupported.append(api)
        }
        if !unsupported.isEmpty {
            reasons.append("Uses unsupported APIs: \(unsupported.joined(separator: ", ")).")
        }
        return CompatibilityReport(compatible: reasons.isEmpty, reasons: reasons,
                                   engineRequirement: manifest.enginesVscode, unsupportedAPIs: unsupported)
    }
}

public struct VSCodeCommand: Codable, Hashable, Sendable {
    public let command: String
    public let title: String
    public let category: String?

    public init(command: String, title: String, category: String? = nil) {
        self.command = command
        self.title = title
        self.category = category
    }
}

public struct VSCodeView: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let when: String?

    public init(id: String, name: String, when: String? = nil) {
        self.id = id
        self.name = name
        self.when = when
    }
}

public struct ConfigurationProperty: Codable, Hashable, Sendable {
    public let type: String?
    public let defaultValue: JSONValue?
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case type
        case defaultValue = "default"
        case description
    }

    public init(type: String? = nil, defaultValue: JSONValue? = nil, description: String? = nil) {
        self.type = type
        self.defaultValue = defaultValue
        self.description = description
    }
}

public struct VSCodeManifest: Sendable {
    public let name: String
    public let publisher: String
    public let version: String
    public let displayName: String?
    public let description: String?
    public let enginesVscode: String?
    public let main: String?
    public let browser: String?
    public let activationEvents: [String]
    public let extensionDependencies: [String]
    public let extensionPack: [String]
    public let categories: [String]
    public let contributesCommands: [VSCodeCommand]
    public let contributesViews: [VSCodeView]
    public let configurationProperties: [String: ConfigurationProperty]
    public let declaredAPIs: [String]

    public var identity: ExtensionIdentity { ExtensionIdentity(publisher: publisher, name: name) }

    public var metadata: ExtensionMetadata {
        ExtensionMetadata(publisher: publisher, name: name, version: version,
                          displayName: displayName ?? name, description: description ?? "",
                          categories: categories, kind: .vscode,
                          engineRequirement: enginesVscode)
    }

    public var allDependencies: [String] { extensionDependencies + extensionPack }
}

public enum VSCodeManifestParser {
    public static func parse(data: Data) throws -> VSCodeManifest {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SwiftCodeExtensionError.manifest("Manifest is not valid JSON: \(error.localizedDescription)")
        }
        guard let dict = object as? [String: Any] else {
            throw SwiftCodeExtensionError.manifest("Manifest must be a JSON object.")
        }
        return try parse(dict: dict)
    }

    public static func parseFile(at url: URL) throws -> VSCodeManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SwiftCodeExtensionError.manifest("Could not read manifest at \(url.path): \(error.localizedDescription)")
        }
        return try parse(data: data)
    }

    public static func isUnsafeRelativePath(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return components.contains { $0 == ".." }
    }

    static func parse(dict: [String: Any]) throws -> VSCodeManifest {
        guard let name = dict["name"] as? String, !name.isEmpty else {
            throw SwiftCodeExtensionError.manifest("Manifest is missing a non-empty 'name'.")
        }
        guard let publisher = dict["publisher"] as? String, !publisher.isEmpty else {
            throw SwiftCodeExtensionError.manifest("Manifest is missing a non-empty 'publisher'.")
        }
        guard let version = dict["version"] as? String,
              SemanticVersion(string: version) != nil else {
            throw SwiftCodeExtensionError.manifest("Manifest 'version' is missing or is not a parseable version.")
        }
        let engines = (dict["engines"] as? [String: Any])?["vscode"] as? String
        let main = dict["main"] as? String
        if let main, isUnsafeRelativePath(main) {
            throw SwiftCodeExtensionError.manifest("Manifest 'main' must be a relative path inside the package.")
        }
        let contributes = dict["contributes"] as? [String: Any] ?? [:]
        var commands: [VSCodeCommand] = []
        if let rawCommands = contributes["commands"] as? [[String: Any]] {
            for raw in rawCommands {
                guard let command = raw["command"] as? String,
                      let title = raw["title"] as? String else {
                    throw SwiftCodeExtensionError.manifest("A contributed command is missing 'command' or 'title'.")
                }
                commands.append(VSCodeCommand(command: command, title: title,
                                              category: raw["category"] as? String))
            }
        }
        var views: [VSCodeView] = []
        if let rawViews = contributes["views"] as? [String: Any] {
            for (_, container) in rawViews {
                guard let entries = container as? [[String: Any]] else { continue }
                for entry in entries {
                    guard let id = entry["id"] as? String, let name = entry["name"] as? String else { continue }
                    views.append(VSCodeView(id: id, name: name, when: entry["when"] as? String))
                }
            }
        }
        var properties: [String: ConfigurationProperty] = [:]
        if let configuration = contributes["configuration"] as? [String: Any],
           let rawProperties = configuration["properties"] as? [String: Any] {
            for (key, value) in rawProperties {
                guard let prop = value as? [String: Any] else { continue }
                let defaultJSON: JSONValue?
                if let rawDefault = prop["default"] {
                    let data = try JSONSerialization.data(withJSONObject: rawDefault)
                    defaultJSON = try JSONDecoder().decode(JSONValue.self, from: data)
                } else {
                    defaultJSON = nil
                }
                properties[key] = ConfigurationProperty(type: prop["type"] as? String,
                                                        defaultValue: defaultJSON,
                                                        description: prop["description"] as? String)
            }
        }
        var declaredAPIs: [String] = []
        if !commands.isEmpty { declaredAPIs.append("commands") }
        if !views.isEmpty { declaredAPIs.append("TreeDataProvider") }
        return VSCodeManifest(
            name: name, publisher: publisher, version: version,
            displayName: dict["displayName"] as? String,
            description: dict["description"] as? String,
            enginesVscode: engines,
            main: main,
            browser: dict["browser"] as? String,
            activationEvents: dict["activationEvents"] as? [String] ?? [],
            extensionDependencies: dict["extensionDependencies"] as? [String] ?? [],
            extensionPack: dict["extensionPack"] as? [String] ?? [],
            categories: dict["categories"] as? [String] ?? [],
            contributesCommands: commands,
            contributesViews: views,
            configurationProperties: properties,
            declaredAPIs: declaredAPIs)
    }
}
