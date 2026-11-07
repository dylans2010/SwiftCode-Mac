import Foundation

public struct XCProjDocument: Sendable, Codable {
    public enum FileItemKind: String, Sendable, Codable {
        case folder
        case group
        case file
    }

    public struct FileItem: Sendable, Codable {
        public var kind: FileItemKind?
        public var path: String?
        public var targetMembership: [String]?
        public var name: String?
        public var children: [FileItem]?
        public var id: String?
        public var type: String?
        public var index: Bool?

        enum CodingKeys: String, CodingKey {
            case kind
            case path
            case targetMembership = "target-membership"
            case name
            case children
            case id
            case type
            case index
        }

        public init(
            kind: FileItemKind? = nil,
            path: String? = nil,
            targetMembership: [String]? = nil,
            name: String? = nil,
            children: [FileItem]? = nil,
            id: String? = nil,
            type: String? = nil,
            index: Bool? = nil
        ) {
            self.kind = kind
            self.path = path
            self.targetMembership = targetMembership
            self.name = name
            self.children = children
            self.id = id
            self.type = type
            self.index = index
        }
    }

    public struct LocalizationsConfig: Sendable, Codable {
        public var development: String
        public var supported: [String]

        public init(development: String = "en", supported: [String] = ["Base"]) {
            self.development = development
            self.supported = supported
        }
    }

    public struct Target: Sendable, Codable {
        public var name: String
        public var id: String
        public var product: String
        public var productType: String
        public var buildPhases: [String]
        public var buildSettings: [String: BuildSettingValue]

        enum CodingKeys: String, CodingKey {
            case name
            case id
            case product
            case productType = "product-type"
            case buildPhases = "build-phases"
            case buildSettings = "build-settings"
        }

        public init(
            name: String,
            id: String,
            product: String,
            productType: String,
            buildPhases: [String] = ["compile-sources", "frameworks", "resources"],
            buildSettings: [String: BuildSettingValue] = [:]
        ) {
            self.name = name
            self.id = id
            self.product = product
            self.productType = productType
            self.buildPhases = buildPhases
            self.buildSettings = buildSettings
        }
    }

    public enum BuildSettingValue: Sendable, Codable, Equatable {
        case string(String)
        case array([String])
        case boolean(Bool)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .string(str)
            } else if let arr = try? container.decode([String].self) {
                self = .array(arr)
            } else if let b = try? container.decode(Bool.self) {
                self = .boolean(b)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid BuildSettingValue")
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s):
                try container.encode(s)
            case .array(let a):
                try container.encode(a)
            case .boolean(let b):
                try container.encode(b)
            }
        }
    }

    public var defaultConfiguration: String
    public var configurations: [String]
    public var localizations: LocalizationsConfig
    public var files: [FileItem]
    public var targets: [Target]
    public var buildSettings: [String: BuildSettingValue]
    public var lastUpgrade: String
    public var lastSwiftUpdate: String

    enum CodingKeys: String, CodingKey {
        case defaultConfiguration = "default-configuration"
        case configurations
        case localizations
        case files
        case targets
        case buildSettings = "build-settings"
        case lastUpgrade = "last-upgrade"
        case lastSwiftUpdate = "last-swift-update"
    }

    public init(
        defaultConfiguration: String = "Release",
        configurations: [String] = ["Debug", "Release"],
        localizations: LocalizationsConfig = LocalizationsConfig(),
        files: [FileItem] = [],
        targets: [Target] = [],
        buildSettings: [String: BuildSettingValue] = [:],
        lastUpgrade: String = "27.0",
        lastSwiftUpdate: String = "27.0"
    ) {
        self.defaultConfiguration = defaultConfiguration
        self.configurations = configurations
        self.localizations = localizations
        self.files = files
        self.targets = targets
        self.buildSettings = buildSettings
        self.lastUpgrade = lastUpgrade
        self.lastSwiftUpdate = lastSwiftUpdate
    }

    public static func locate(_ path: String) -> (file: URL, projectName: String) {
        var url = URL(fileURLWithPath: path)
        if url.pathExtension == "xcodeproj" {
            let xcproj = url.appendingPathComponent("project.xcproj")
            if FileManager.default.fileExists(atPath: xcproj.path) {
                url = xcproj
            } else {
                url = url.appendingPathComponent("project.pbxproj")
            }
        }
        let bundle = url.deletingLastPathComponent()
        let name = bundle.pathExtension == "xcodeproj" ? bundle.deletingPathExtension().lastPathComponent : bundle.lastPathComponent
        return (url, name)
    }

    public static func load(from url: URL) throws -> XCProjDocument {
        let rawData = try Data(contentsOf: url)
        return try decode(from: rawData)
    }

    public static func decode(from data: Data) throws -> XCProjDocument {
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "XCProjDocument", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 data"])
        }
        // Normalize trailing commas in JSON before decoding
        let sanitized = sanitizeJSONTrailingCommas(text)
        guard let cleanData = sanitized.data(using: .utf8) else {
            throw NSError(domain: "XCProjDocument", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to sanitize JSON"])
        }
        return try JSONDecoder().decode(XCProjDocument.self, from: cleanData)
    }

    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func write(to url: URL) throws {
        let data = try encode()
        try data.write(to: url, options: .atomic)
    }

    private static func sanitizeJSONTrailingCommas(_ json: String) -> String {
        // Regex to remove trailing commas before closing braces/brackets
        var result = json
        result = result.replacingOccurrences(of: ",\\s*([}\\]])", with: "$1", options: .regularExpression)
        return result
    }
}
