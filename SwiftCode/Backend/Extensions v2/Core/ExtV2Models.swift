import Foundation

// MARK: - Extensions v2 core models
//
// All Extensions v2 types carry the `ExtV2` prefix on purpose: the app
// already has a legacy `ExtensionManager` / `ExtensionManifest` pair in
// `SwiftCode/Services` and a second `ExtensionManifest` in `SwiftCode/SDK`.
// Prefixing keeps the new platform unambiguous and avoids silent overloads.

/// A stable extension identity. The `publisher.name` string is the lookup
/// key everywhere (UI, storage, host, Assist); display names are never
/// used as keys because two publishers may ship the same display name.
public struct ExtV2Identity: Codable, Hashable, Sendable, CustomStringConvertible {
    public let publisher: String
    public let name: String

    public var id: String { "\(publisher).\(name)" }
    public var description: String { id }

    public init(publisher: String, name: String) {
        self.publisher = publisher
        self.name = name
    }

    /// Parses `publisher.name`. Returns nil when there is no publisher part.
    public init?(id: String) {
        guard let dot = id.firstIndex(of: ".") else { return nil }
        let publisher = String(id[..<dot])
        let name = String(id[id.index(after: dot)...])
        guard !publisher.isEmpty, !name.isEmpty else { return nil }
        self.publisher = publisher
        self.name = name
    }
}

/// Which runtime an extension belongs to. These are three distinct
/// ecosystems, not three labels for the same thing (see Docs/Extensions-v2.md).
public enum ExtV2Kind: String, Codable, Sendable, CaseIterable {
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

/// Lifecycle state, always derived from the authoritative manager/storage,
/// never guessed by a view.
public enum ExtV2State: String, Codable, Sendable, CaseIterable {
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

/// A capability an extension may declare. A prompt is not a sandbox:
/// capabilities gate what the bridges will actually do, and revocation
/// takes effect on the next call (see ExtV2PermissionManager).
public enum ExtV2Capability: String, Codable, Sendable, CaseIterable {
    case workspaceRead
    case workspaceWrite
    case outsideWorkspace
    case network
    case terminal
    case process
    case secrets
    case sourceControl
    case build
    case assistTools
    case projectConfig
    case webview

    public var displayName: String {
        switch self {
        case .workspaceRead: return "Read workspace files"
        case .workspaceWrite: return "Write workspace files"
        case .outsideWorkspace: return "Access files outside the workspace"
        case .network: return "Network access"
        case .terminal: return "Run terminal commands"
        case .process: return "Launch processes"
        case .secrets: return "Read stored secrets"
        case .sourceControl: return "Source-control operations"
        case .build: return "Build and test execution"
        case .assistTools: return "Register Assist tools"
        case .projectConfig: return "Change project configuration"
        case .webview: return "Show webviews"
        }
    }
}

/// Registry / local metadata. Download counts and ratings are deliberately
/// absent: they are not part of the compatibility contract and must never
/// be fabricated when a registry does not report them.
public struct ExtV2ExtensionMetadata: Codable, Hashable, Sendable, Identifiable {
    public let publisher: String
    public let name: String
    public let version: String
    public let displayName: String
    public let description: String
    public let categories: [String]
    public let kind: ExtV2Kind
    public let license: String?
    public let homepage: String?
    public let repository: String?
    public let downloadURL: URL?
    public let engineRequirement: String?

    public var id: String { "\(publisher).\(name)" }
    public var identity: ExtV2Identity { ExtV2Identity(publisher: publisher, name: name) }

    public init(
        publisher: String, name: String, version: String, displayName: String,
        description: String, categories: [String] = [], kind: ExtV2Kind = .vscode,
        license: String? = nil, homepage: String? = nil, repository: String? = nil,
        downloadURL: URL? = nil, engineRequirement: String? = nil
    ) {
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

/// One installed extension, as persisted by ExtV2Storage.
public struct ExtV2InstalledExtension: Codable, Hashable, Sendable, Identifiable {
    public let metadata: ExtV2ExtensionMetadata
    public var isEnabled: Bool
    public var state: ExtV2State
    public var installPath: String
    public var dependencies: [String]
    public var capabilities: [ExtV2Capability]
    public var lastError: String?
    public var updatedAt: Date

    public var id: String { metadata.id }
    public var identity: ExtV2Identity { metadata.identity }

    public init(
        metadata: ExtV2ExtensionMetadata, isEnabled: Bool = true,
        state: ExtV2State = .installed, installPath: String,
        dependencies: [String] = [], capabilities: [ExtV2Capability] = [],
        lastError: String? = nil, updatedAt: Date = Date()
    ) {
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

/// An available update, computed by comparing registry metadata against the
/// installed record — never assumed from a search listing alone.
public struct ExtV2UpdateInfo: Hashable, Sendable, Identifiable {
    public let installed: ExtV2InstalledExtension
    public let latest: ExtV2ExtensionMetadata
    public var id: String { installed.id }
}

/// Errors surfaced to the UI. Every case carries a human-readable message;
/// no error is ever a bare success or a swallowed failure.
public enum ExtV2Error: Error, LocalizedError, Sendable {
    case notInstalled(String)
    case disabled(String)
    case incompatible(String)
    case missingDependencies([String])
    case permissionDenied(ExtV2Capability)
    case registry(String)
    case network(String)
    case package(String)
    case manifest(String)
    case host(String)
    case timeout(String)
    case invalidRequest(String)
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let id): return "Extension '\(id)' is not installed."
        case .disabled(let id): return "Extension '\(id)' is disabled."
        case .incompatible(let why): return "Incompatible extension: \(why)"
        case .missingDependencies(let ids): return "Missing dependencies: \(ids.joined(separator: ", "))"
        case .permissionDenied(let cap): return "Permission denied: \(cap.displayName). Grant it in Extensions > Permissions."
        case .registry(let m), .network(let m), .package(let m), .manifest(let m),
             .host(let m), .timeout(let m), .invalidRequest(let m), .unknown(let m):
            return m
        case .cancelled: return "Operation cancelled."
        }
    }
}
