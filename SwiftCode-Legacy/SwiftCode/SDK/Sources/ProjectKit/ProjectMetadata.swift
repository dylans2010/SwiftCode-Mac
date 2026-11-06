import Foundation
import DiagnosticsKit
import WorkspaceKit

public enum ProjectType: String, Codable, Sendable, CaseIterable {
    case swiftPackage = "swift-package"
    case xcodeProject = "xcode-project"
    case swiftcodeExtension = "swiftcode-extension"
    case typescriptExtension = "typescript-extension"
    case automationExtension = "automation-extension"
    case sourceControlExtension = "source-control-extension"
    case macosApp = "macos-app"

    public var displayName: String {
        switch self {
        case .swiftPackage: return "Swift Package"
        case .xcodeProject: return "Xcode Project"
        case .swiftcodeExtension: return "SwiftCode Extension"
        case .typescriptExtension: return "TypeScript Extension"
        case .automationExtension: return "SwiftCode Automation Extension"
        case .sourceControlExtension: return "SwiftCode Source Control Extension"
        case .macosApp: return "macOS App"
        }
    }
}

public struct ProjectTarget: Codable, Sendable, Equatable {
    public let name: String
    public let type: String
    public let sourceFiles: [String]
    public let dependencies: [String]

    public init(name: String, type: String = "library", sourceFiles: [String] = [], dependencies: [String] = []) {
        self.name = name
        self.type = type
        self.sourceFiles = sourceFiles
        self.dependencies = dependencies
    }
}

public struct ProjectMetadata: Codable, Sendable {
    public let id: String
    public let name: String
    public let type: ProjectType
    public let version: String
    public let rootPath: String
    public let targets: [ProjectTarget]
    public let configurations: [String]
    public let customProperties: [String: String]

    public init(
        id: String,
        name: String,
        type: ProjectType,
        version: String,
        rootPath: String,
        targets: [ProjectTarget] = [],
        configurations: [String] = ["Debug", "Release"],
        customProperties: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.version = version
        self.rootPath = rootPath
        self.targets = targets
        self.configurations = configurations
        self.customProperties = customProperties
    }
}
