import Foundation

/// VS Code / v2 identity: `"<publisher>.<name>"`. It is the lookup key
/// everywhere (UI, storage, host, Assist); display names are never keys.
/// Parsing splits on the **first** `.`; both parts must be non-empty.
public struct ExtensionIdentity: Codable, Hashable, Sendable, CustomStringConvertible {
    public let publisher: String
    public let name: String

    public var id: String { "\(publisher).\(name)" }
    public var description: String { id }

    public init(publisher: String, name: String) {
        self.publisher = publisher
        self.name = name
    }

    public init?(id: String) {
        guard let dot = id.firstIndex(of: ".") else { return nil }
        let publisher = String(id[id.startIndex..<dot])
        let name = String(id[id.index(after: dot)...])
        guard !publisher.isEmpty, !name.isEmpty else { return nil }
        self.publisher = publisher
        self.name = name
    }
}

public enum ExtensionKind: String, Codable, Sendable, CaseIterable {
    case vscode
    case native
    case xcodeCommand

    public var displayName: String {
        switch self {
        case .vscode: return "VS Code"
        case .native: return "SwiftCode Native"
        case .xcodeCommand: return "Xcode Command"
        }
    }
}

/// The user-visible lifecycle state (spec §3.2). `activationFailed` is
/// declared for wire/source compatibility; no transition into it is
/// specified in this wave — activation failures surface as thrown
/// errors and a stopped host instead.
public enum ExtensionState: String, Codable, Sendable, CaseIterable {
    case notInstalled
    case installed
    case disabled
    case enabled
    case incompatible
    case missingDependencies
    case activationFailed
    case running
    case crashed
    case unavailable

    public var displayName: String {
        switch self {
        case .notInstalled: return "Not Installed"
        case .installed: return "Installed"
        case .disabled: return "Disabled"
        case .enabled: return "Enabled"
        case .incompatible: return "Incompatible"
        case .missingDependencies: return "Missing Dependencies"
        case .activationFailed: return "Activation Failed"
        case .running: return "Running"
        case .crashed: return "Crashed"
        case .unavailable: return "Unavailable"
        }
    }
}

public struct ExtensionMetadata: Codable, Hashable, Sendable, Identifiable {
    public let publisher: String
    public let name: String
    public let version: String
    public let displayName: String
    public let description: String
    public let categories: [String]
    public let kind: ExtensionKind
    public let license: String?
    public let homepage: String?
    public let repository: String?
    public let downloadURL: URL?
    public let engineRequirement: String?

    public var id: String { "\(publisher).\(name)" }
    public var identity: ExtensionIdentity { ExtensionIdentity(publisher: publisher, name: name) }

    public init(publisher: String, name: String, version: String, displayName: String,
                description: String, categories: [String] = [], kind: ExtensionKind = .vscode,
                license: String? = nil, homepage: String? = nil, repository: String? = nil,
                downloadURL: URL? = nil, engineRequirement: String? = nil) {
        self.publisher = publisher
        self.name = name
        self.version = version
        self.displayName = displayName
        self.description = description
        self.categories = categories
        self.kind = kind
        self.license = license
        self.homepage = homepage
        self.repository = repository
        self.downloadURL = downloadURL
        self.engineRequirement = engineRequirement
    }
}

public struct InstalledExtension: Codable, Hashable, Sendable, Identifiable {
    public let metadata: ExtensionMetadata
    public var isEnabled: Bool
    public var state: ExtensionState
    public var installPath: String
    public var dependencies: [String]
    public var capabilities: [ExtensionCapability]
    public var lastError: String?
    public var updatedAt: Date

    public var id: String { metadata.id }
    public var identity: ExtensionIdentity { metadata.identity }

    public init(metadata: ExtensionMetadata, isEnabled: Bool = true,
                state: ExtensionState = .installed, installPath: String,
                dependencies: [String] = [], capabilities: [ExtensionCapability] = [],
                lastError: String? = nil, updatedAt: Date = Date()) {
        self.metadata = metadata
        self.isEnabled = isEnabled
        self.state = state
        self.installPath = installPath
        self.dependencies = dependencies
        self.capabilities = capabilities
        self.lastError = lastError
        self.updatedAt = updatedAt
    }
}

public struct ExtensionUpdateInfo: Hashable, Sendable, Identifiable {
    public let installed: InstalledExtension
    public let latest: ExtensionMetadata
    public var id: String { installed.id }

    public init(installed: InstalledExtension, latest: ExtensionMetadata) {
        self.installed = installed
        self.latest = latest
    }
}

public struct ExtensionContributionCommand: Codable, Hashable, Sendable {
    public let command: String
    public let title: String

    public init(command: String, title: String) {
        self.command = command
        self.title = title
    }
}

public struct ExtensionContributionView: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ExtensionTreeItem: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?
    public let command: String?

    public init(id: String, label: String, description: String?, command: String?) {
        self.id = id
        self.label = label
        self.description = description
        self.command = command
    }
}

public struct ExtensionContribution: Codable, Sendable {
    public let commands: [ExtensionContributionCommand]
    public let views: [ExtensionContributionView]
    public let treeItems: [ExtensionTreeItem]
    public let statusBarText: String?
    public let outputLines: [String]
    public let webviewHTML: String?

    public init(commands: [ExtensionContributionCommand] = [], views: [ExtensionContributionView] = [],
                treeItems: [ExtensionTreeItem] = [], statusBarText: String? = nil,
                outputLines: [String] = [], webviewHTML: String? = nil) {
        self.commands = commands
        self.views = views
        self.treeItems = treeItems
        self.statusBarText = statusBarText
        self.outputLines = outputLines
        self.webviewHTML = webviewHTML
    }

    public static let empty = ExtensionContribution()
}
