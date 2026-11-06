import Foundation
import DiagnosticsKit

public struct ExtensionRuntime: Codable, Sendable, Equatable {
    public let language: String
    public let entrypoint: String
    public let minimumSwiftCodeVersion: String

    public init(language: String = "typescript", entrypoint: String = "dist/index.js", minimumSwiftCodeVersion: String = "1.0.0") {
        self.language = language
        self.entrypoint = entrypoint
        self.minimumSwiftCodeVersion = minimumSwiftCodeVersion
    }
}

public struct ExtensionSDKRef: Codable, Sendable, Equatable {
    public let name: String
    public let versionRange: String
    public let protocolVersion: Int

    public init(name: String = "@swiftcode/sdk", versionRange: String = "^1.0.0", protocolVersion: Int = 1) {
        self.name = name
        self.versionRange = versionRange
        self.protocolVersion = protocolVersion
    }
}

public struct ExtensionCommandContribution: Codable, Sendable, Equatable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct ExtensionContributions: Codable, Sendable, Equatable {
    public let commands: [ExtensionCommandContribution]

    public init(commands: [ExtensionCommandContribution] = []) {
        self.commands = commands
    }
}

public struct ExtensionAssist: Codable, Sendable, Equatable {
    public let requested: Bool

    public init(requested: Bool = false) {
        self.requested = requested
    }
}

public struct ExtensionManifest: Codable, Sendable, Equatable {
    public let manifestVersion: Int
    public let id: String
    public let name: String
    public let version: String
    public let description: String?
    public let type: String
    public let runtime: ExtensionRuntime
    public let sdk: ExtensionSDKRef
    public let capabilities: [ExtensionCapabilityDeclaration]
    public let contributes: ExtensionContributions?
    public let assist: ExtensionAssist

    public init(
        manifestVersion: Int = 1,
        id: String,
        name: String,
        version: String = "1.0.0",
        description: String? = nil,
        type: String = "extension",
        runtime: ExtensionRuntime = ExtensionRuntime(),
        sdk: ExtensionSDKRef = ExtensionSDKRef(),
        capabilities: [ExtensionCapabilityDeclaration] = [],
        contributes: ExtensionContributions? = nil,
        assist: ExtensionAssist = ExtensionAssist()
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
    }
}
