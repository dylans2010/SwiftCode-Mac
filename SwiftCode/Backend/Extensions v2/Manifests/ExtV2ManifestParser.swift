import Foundation

// MARK: - VS Code extension manifest (package.json)
//
// Decoding is deliberately tolerant: unknown keys are ignored, every
// known key is optional except the identity triple (name, publisher,
// version). A manifest that fails validation is reported, never loaded
// with invented defaults for its identity.

public struct ExtV2VSCodeCommand: Codable, Hashable, Sendable {
    public let command: String
    public let title: String
    public let category: String?

    public init(command: String, title: String, category: String? = nil) {
        self.command = command; self.title = title; self.category = category
    }
}

public struct ExtV2VSCodeView: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let when: String?

    public init(id: String, name: String, when: String? = nil) {
        self.id = id; self.name = name; self.when = when
    }
}

public struct ExtV2VSCodeManifest: Sendable {
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
    public let contributesCommands: [ExtV2VSCodeCommand]
    public let contributesViews: [ExtV2VSCodeView]
    public let configurationProperties: [String: ExtV2ConfigurationProperty]
    /// API names the extension declares in `contributes` / known keys, used
    /// only for the compatibility report — never a claim of support.
    public let declaredAPIs: [String]

    public var identity: ExtV2Identity { ExtV2Identity(publisher: publisher, name: name) }
    public var metadata: ExtV2ExtensionMetadata {
        ExtV2ExtensionMetadata(
            publisher: publisher, name: name, version: version,
            displayName: displayName ?? name, description: description ?? "",
            categories: categories, kind: .vscode, engineRequirement: enginesVscode)
    }

    public var allDependencies: [String] { extensionDependencies + extensionPack }
}

public struct ExtV2ConfigurationProperty: Codable, Hashable, Sendable {
    public let type: String?
    public let defaultValue: ExtV2JSONValue?
    public let description: String?

    enum CodingKeys: String, CodingKey {
        case type
        case defaultValue = "default"
        case description
    }
}

public enum ExtV2ManifestParser {
    private struct RawManifest: Decodable {
        var name: String?
        var publisher: String?
        var version: String?
        var displayName: String?
        var description: String?
        var engines: [String: String]?
        var main: String?
        var browser: String?
        var activationEvents: [String]?
        var extensionDependencies: [String]?
        var extensionPack: [String]?
        var categories: [String]?
        var contributes: RawContributes?

        struct RawContributes: Decodable {
            var commands: [ExtV2VSCodeCommand]?
            var views: [String: [ExtV2VSCodeView]]?
            var configuration: RawConfiguration?
            struct RawConfiguration: Decodable {
                var properties: [String: ExtV2ConfigurationProperty]?
            }
        }
    }

    /// Parses and validates a package.json payload. Throws ExtV2Error.manifest
    /// with a specific reason; callers surface that reason verbatim.
    public static func parse(data: Data) throws -> ExtV2VSCodeManifest {
        let raw: RawManifest
        do {
            raw = try JSONDecoder().decode(RawManifest.self, from: data)
        } catch {
            throw ExtV2Error.manifest("package.json is not valid JSON: \(error.localizedDescription)")
        }
        guard let name = raw.name, !name.isEmpty else {
            throw ExtV2Error.manifest("package.json is missing a non-empty 'name'.")
        }
        guard let publisher = raw.publisher, !publisher.isEmpty else {
            throw ExtV2Error.manifest("package.json is missing a non-empty 'publisher'.")
        }
        guard let version = raw.version, ExtV2Version(string: version) != nil else {
            throw ExtV2Error.manifest("package.json 'version' is missing or not a semantic version.")
        }
        if let main = raw.main, isUnsafeRelativePath(main) {
            throw ExtV2Error.manifest("Manifest 'main' entry point escapes the package: \(main)")
        }
        var declaredAPIs: [String] = []
        if let contributes = raw.contributes {
            if contributes.commands?.isEmpty == false { declaredAPIs.append("commands") }
            if contributes.views?.isEmpty == false { declaredAPIs.append("TreeDataProvider") }
        }
        return ExtV2VSCodeManifest(
            name: name, publisher: publisher, version: version,
            displayName: raw.displayName, description: raw.description,
            enginesVscode: raw.engines?["vscode"], main: raw.main, browser: raw.browser,
            activationEvents: raw.activationEvents ?? [],
            extensionDependencies: raw.extensionDependencies ?? [],
            extensionPack: raw.extensionPack ?? [],
            categories: raw.categories ?? [],
            contributesCommands: raw.contributes?.commands ?? [],
            contributesViews: raw.contributes?.views?.values.flatMap { $0 } ?? [],
            configurationProperties: raw.contributes?.configuration?.properties ?? [:],
            declaredAPIs: declaredAPIs
        )
    }

    public static func parseFile(at url: URL) throws -> ExtV2VSCodeManifest {
        try parse(data: Data(contentsOf: url))
    }

    static func isUnsafeRelativePath(_ path: String) -> Bool {
        path.hasPrefix("/") || path.split(separator: "/").contains("..")
    }
}
